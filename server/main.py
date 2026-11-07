import re
import json
import subprocess
import shutil
import os
import sqlite3
import datetime
import secrets
import smtplib
import time
import uuid
import threading
import requests
from urllib.parse import urlparse
from typing import Optional, List
from email.message import EmailMessage
from fastapi import FastAPI, HTTPException, Query, Request, UploadFile, File, Form, BackgroundTasks
from fastapi.responses import StreamingResponse, FileResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="钞机汇玩视频提取引擎", version="2.5.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_PATH = "/root/database.db"
VIDEO_CACHE_DIR = "/root/videos"
IMAGE_REPAIR_DIR = "/root/image_repairs"
ADMIN_PASSWORD = "Aa123450."  # 管理员后台登录密码

def init_db():
    os.makedirs(VIDEO_CACHE_DIR, exist_ok=True)
    os.makedirs(IMAGE_REPAIR_DIR, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    CREATE TABLE IF NOT EXISTS users (
        user_id TEXT PRIMARY KEY,
        daily_quota INTEGER DEFAULT 10,
        bonus_quota INTEGER DEFAULT 0,
        is_vip INTEGER DEFAULT 0,
        vip_expire_at TEXT,
        is_banned INTEGER DEFAULT 0,
        last_active_date TEXT,
        created_at TEXT
    )
    """)
    try:
        cur.execute("ALTER TABLE users ADD COLUMN is_banned INTEGER DEFAULT 0")
    except Exception:
        pass

    cur.execute("""
    CREATE TABLE IF NOT EXISTS cards (
        card_key TEXT PRIMARY KEY,
        card_type TEXT,
        card_val INTEGER,
        is_used INTEGER DEFAULT 0,
        used_by TEXT,
        used_at TEXT,
        created_at TEXT
    )
    """)
    # 每日免费额度统一为 10 次；额外充值次数保存在 bonus_quota。
    cur.execute("UPDATE users SET daily_quota = MIN(COALESCE(daily_quota, 0), 10)")
    cur.execute("""
    CREATE TABLE IF NOT EXISTS parse_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        platform TEXT,
        url TEXT,
        title TEXT,
        created_at TEXT
    )
    """)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS feedback (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        content TEXT NOT NULL,
        contact TEXT,
        client_info TEXT,
        created_at TEXT,
        status TEXT DEFAULT 'new'
    )
    """)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actor TEXT NOT NULL DEFAULT 'system',
        action TEXT NOT NULL,
        target_user_id TEXT,
        detail TEXT,
        created_at TEXT NOT NULL
    )
    """)
    conn.commit()
    conn.close()

init_db()

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def cleanup_expired_data():
    """清理24小时前的临时文件和30天前的服务记录。"""
    file_cutoff = time.time() - 24 * 60 * 60
    removed_files = 0
    for directory in (VIDEO_CACHE_DIR, IMAGE_REPAIR_DIR):
        try:
            for name in os.listdir(directory):
                path = os.path.join(directory, name)
                if os.path.isfile(path) and os.path.getmtime(path) < file_cutoff:
                    os.remove(path)
                    removed_files += 1
        except Exception as exc:
            print(f"[cleanup] file cleanup failed for {directory}: {exc}")

    record_cutoff = (
        datetime.datetime.now() - datetime.timedelta(days=30)
    ).strftime("%Y-%m-%d %H:%M:%S")
    removed_records = 0
    try:
        conn = get_db()
        for table in ("parse_logs", "audit_logs", "feedback"):
            cursor = conn.execute(
                f"DELETE FROM {table} WHERE created_at < ?",
                (record_cutoff,),
            )
            removed_records += max(0, cursor.rowcount)
        conn.commit()
        conn.close()
    except Exception as exc:
        print(f"[cleanup] database cleanup failed: {exc}")

    print(f"[cleanup] removed files={removed_files}, records={removed_records}")

def cleanup_worker():
    while True:
        cleanup_expired_data()
        time.sleep(6 * 60 * 60)

@app.on_event("startup")
def start_cleanup_worker():
    threading.Thread(
        target=cleanup_worker,
        name="retention-cleanup",
        daemon=True,
    ).start()

def write_audit_log(action: str, target_user_id: str = "", detail: str = "", actor: str = "system"):
    """写入后台审计日志；失败不影响用户的正常请求。"""
    try:
        conn = get_db()
        conn.execute(
            "INSERT INTO audit_logs (actor, action, target_user_id, detail, created_at) VALUES (?, ?, ?, ?, ?)",
            (
                (actor or "system")[:30],
                (action or "unknown")[:50],
                (target_user_id or "")[:120],
                (detail or "")[:500],
                datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            ),
        )
        conn.commit()
        conn.close()
    except Exception as exc:
        print(f"[audit] write failed: {exc}")

def get_or_create_user(user_id: str):
    conn = get_db()
    cur = conn.cursor()
    today = datetime.date.today().strftime("%Y-%m-%d")
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    cur.execute("SELECT * FROM users WHERE user_id = ?", (user_id,))
    row = cur.fetchone()

    is_new_user = not row
    if is_new_user:
        cur.execute(
            "INSERT INTO users (user_id, daily_quota, bonus_quota, is_vip, is_banned, last_active_date, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (user_id, 10, 0, 0, 0, today, now_str)
        )
        conn.commit()
        cur.execute("SELECT * FROM users WHERE user_id = ?", (user_id,))
        row = cur.fetchone()
    else:
        if row["last_active_date"] != today:
            cur.execute("UPDATE users SET daily_quota = 10, last_active_date = ? WHERE user_id = ?", (today, user_id))
            conn.commit()
            cur.execute("SELECT * FROM users WHERE user_id = ?", (user_id,))
            row = cur.fetchone()

    user = dict(row)
    conn.close()
    if is_new_user:
        write_audit_log("new_user", user_id, "首次进入小程序")
    return user

def deduct_user_quota(user_id: str) -> bool:
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE user_id = ?", (user_id,))
    user = cur.fetchone()
    if not user:
        conn.close()
        return False

    if user["is_banned"]:
        conn.close()
        return False

    if user["is_vip"] == 1:
        if user["vip_expire_at"]:
            now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            if user["vip_expire_at"] > now_str:
                conn.close()
                return True
        else:
            conn.close()
            return True

    if user["daily_quota"] > 0:
        cur.execute("UPDATE users SET daily_quota = daily_quota - 1 WHERE user_id = ?", (user_id,))
        conn.commit()
        conn.close()
        return True
    
    if user["bonus_quota"] > 0:
        cur.execute("UPDATE users SET bonus_quota = bonus_quota - 1 WHERE user_id = ?", (user_id,))
        conn.commit()
        conn.close()
        return True

    conn.close()
    return False

def parse_douyin(url: str):
    headers = {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
    }
    r = requests.get(url, headers=headers, allow_redirects=True, timeout=10)
    final_url = r.url
    match = re.search(r"/(?:video|note)/(\d+)", final_url)
    if not match:
        match = re.search(r"/(\d{15,25})", final_url)
    if not match:
        raise ValueError("无法提取抖音视频或图集 ID")
    item_id = match.group(1)

    endpoints = [
        f"https://api3-normal-c-hl.amemv.com/aweme/v1/feed/?aweme_id={item_id}",
        f"https://api5-normal-c-hl.amemv.com/aweme/v1/feed/?aweme_id={item_id}",
        f"https://aweme-hl.snssdk.com/aweme/v1/feed/?aweme_id={item_id}"
    ]

    feed_headers = {"User-Agent": "okhttp/3.10.0.1"}
    aweme = None
    for ep in endpoints:
        try:
            resp = requests.get(ep, headers=feed_headers, timeout=8)
            if resp.status_code == 200:
                data = resp.json()
                items = data.get("aweme_list", [])
                if items and len(items) > 0:
                    aweme = items[0]
                    break
        except Exception:
            continue

    if not aweme:
        raise ValueError("获取抖音详情失败，作品可能已被创作者删除或设为私密")

    title = aweme.get("desc", "抖音无水印作品")
    author = aweme.get("author", {}).get("nickname", "抖音创作者")
    video = aweme.get("video", {})
    cover = video.get("cover", {}).get("url_list", [""])[0]

    # 图集
    images = aweme.get("images")
    if images and len(images) > 0:
        img_list = []
        for img in images:
            urls = img.get("url_list", [])
            if urls:
                img_list.append(urls[-1])
        return {
            "type": "image",
            "title": title,
            "author": author,
            "cover": cover,
            "images": img_list,
            "video_url": "",
            "origin_url": ""
        }

    # 视频
    play_addr = video.get("play_addr", {}).get("url_list", [])
    if not play_addr:
        raise ValueError("未找到抖音无水印播放地址")

    raw_play_url = play_addr[0].replace("playwm", "play")
    return {
        "type": "video",
        "title": title,
        "author": author,
        "cover": cover,
        "images": [],
        "video_url": f"/api/proxy?url={requests.utils.quote(raw_play_url)}",
        "origin_url": raw_play_url
    }

def parse_kuaishou(url: str):
    headers = {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
        "Cookie": "did=web_default_kuaishou_cookie;"
    }
    r = requests.get(url, headers=headers, allow_redirects=True, timeout=10)
    html = r.text

    # 1. 尝试提取 INIT_STATE 或 pageData
    page_data = None
    if "INIT_STATE" in html:
        idx = html.find("INIT_STATE")
        eq_idx = html.find("=", idx)
        end_idx = html.find("</script>", eq_idx)
        raw_json = html[eq_idx+1:end_idx].strip()
        if raw_json.endswith(";"):
            raw_json = raw_json[:-1]
        try:
            page_data = json.loads(raw_json)
        except Exception:
            pass

    if not page_data:
        m = re.search(r"window\.pageData\s*=\s*(\{.*?\})</script>", html)
        if m:
            page_data = json.loads(m.group(1))

    if not page_data:
        raise ValueError("快手页面结构发生变动，未能提取数据对象")

    # 2. 深入多层结构寻址 photo / video 作品对象
    photo = None
    if isinstance(page_data, dict):
        if "photo" in page_data and isinstance(page_data["photo"], dict):
            photo = page_data["photo"]
        elif "video" in page_data and isinstance(page_data["video"], dict):
            photo = page_data["video"]
        else:
            for k, v in page_data.items():
                if isinstance(v, dict):
                    if "photo" in v and isinstance(v["photo"], dict):
                        photo = v["photo"]
                        break
                    elif "video" in v and isinstance(v["video"], dict):
                        photo = v["video"]
                        break
                    elif "photoUrl" in v or "mainMvUrls" in v or "singlePicture" in v:
                        photo = v
                        break

    if not photo:
        raise ValueError("未找到快手作品数据节点")

    title = photo.get("caption", "快手无水印作品")
    author = photo.get("userName", photo.get("author", {}).get("name", "快手用户"))
    cover = photo.get("poster", photo.get("coverUrl", ""))
    if not cover and photo.get("coverUrls") and len(photo["coverUrls"]) > 0:
        cover = photo["coverUrls"][0].get("url", "")

    # 3. 单张图片 / 图集处理
    is_pic = photo.get("singlePicture") or photo.get("photoType") == "SINGLE_PICTURE"
    if is_pic:
        img_url = cover
        return {
            "type": "image",
            "title": title,
            "author": author,
            "cover": cover,
            "images": [img_url] if img_url else [],
            "video_url": "",
            "origin_url": ""
        }

    # 多张图集
    if "imageShareInfo" in photo or "images" in photo:
        imgs = photo.get("images", [])
        if imgs:
            img_list = []
            for i in imgs:
                if isinstance(i, dict):
                    if "url" in i:
                        img_list.append(i["url"])
                    elif "path" in i:
                        img_list.append("https://" + photo.get("imageCDN", "") + i["path"])
                elif isinstance(i, str):
                    img_list.append(i)
            if img_list:
                return {
                    "type": "image",
                    "title": title,
                    "author": author,
                    "cover": cover or img_list[0],
                    "images": img_list,
                    "video_url": "",
                    "origin_url": ""
                }

    # 4. 视频无水印直链提取
    raw_play_url = photo.get("photoUrl", photo.get("src", ""))
    if not raw_play_url and photo.get("mainMvUrls") and len(photo["mainMvUrls"]) > 0:
        raw_play_url = photo["mainMvUrls"][0].get("url", "")

    if not raw_play_url:
        if cover:
            return {
                "type": "image",
                "title": title,
                "author": author,
                "cover": cover,
                "images": [cover],
                "video_url": "",
                "origin_url": ""
            }
        raise ValueError("无法提取快手作品播放地址")

    return {
        "type": "video",
        "title": title,
        "author": author,
        "cover": cover,
        "images": [],
        "video_url": f"/api/proxy?url={requests.utils.quote(raw_play_url)}",
        "origin_url": raw_play_url
    }

def parse_xiaohongshu(url: str):
    headers = {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
    }
    r = requests.get(url, headers=headers, allow_redirects=True, timeout=10)
    html = r.text

    note = None
    # 优先匹配 __SETUP_SERVER_STATE__ (新版小红书 SSR 数据)
    m_setup = re.search(r"window\.__SETUP_SERVER_STATE__\s*=\s*(\{.*?\})\s*</script>", html, re.DOTALL)
    if m_setup:
        try:
            d_setup = json.loads(m_setup.group(1).replace("undefined", "null"))
            note = d_setup.get("LAUNCHER_SSR_STORE_PAGE_DATA", {}).get("noteData")
        except Exception:
            pass

    # 备用匹配 __INITIAL_STATE__
    if not note:
        match = re.search(r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\})\s*</script>", html, re.DOTALL)
        if match:
            try:
                data = json.loads(match.group(1).replace("undefined", "null"))
                if "noteData" in data and isinstance(data["noteData"], dict):
                    note = data["noteData"].get("data", {}).get("noteData") or data["noteData"].get("noteData") or data["noteData"]
                elif "note" in data and "noteDetailMap" in data["note"]:
                    note_map = data["note"]["noteDetailMap"]
                    if note_map:
                        first_key = list(note_map.keys())[0]
                        note = note_map[first_key].get("note", {})
            except Exception:
                pass

    if not note:
        raise ValueError("未能找到小红书笔记详细数据")

    title = note.get("title") or note.get("desc") or "小红书无水印作品"
    author = note.get("user", {}).get("nickname", "小红书用户")
    cover = note.get("cover", {}).get("urlDefault", "")

    # 图集
    image_list = note.get("imageList", [])
    if image_list and not note.get("video"):
        imgs = []
        for img in image_list:
            info_list = img.get("infoList", [])
            if info_list:
                imgs.append(info_list[-1].get("url", ""))
            elif img.get("urlDefault"):
                imgs.append(img.get("urlDefault"))
        return {
            "type": "image",
            "title": title,
            "author": author,
            "cover": cover,
            "images": imgs,
            "video_url": "",
            "origin_url": ""
        }

    # 视频提取 (兼容旧版 media 及新版 mediaV2 json 格式)
    video_info = note.get("video", {})
    raw_play_url = ""

    # 优先解析 mediaV2
    v2 = video_info.get("mediaV2")
    if isinstance(v2, str):
        try: v2 = json.loads(v2)
        except Exception: pass
    if isinstance(v2, dict):
        stream_v2 = v2.get("video", {}).get("stream", {}) or v2.get("stream", {}) or video_info.get("stream", {})
        for k in ["h264", "h265", "av1", "h266"]:
            for item in stream_v2.get(k, []):
                raw_play_url = item.get("master_url") or item.get("masterUrl") or item.get("main_url")
                if not raw_play_url and item.get("backup_urls"):
                    raw_play_url = item["backup_urls"][0]
                if raw_play_url:
                    break
            if raw_play_url:
                break

    # 备用解析 media
    if not raw_play_url:
        media = video_info.get("media", {})
        stream = media.get("stream", {})
        for k in ["h264", "h265", "av1"]:
            for item in stream.get(k, []):
                raw_play_url = item.get("masterUrl") or item.get("master_url")
                if raw_play_url:
                    break
            if raw_play_url:
                break

    if not raw_play_url:
        raise ValueError("无法提取小红书无水印视频地址")

    return {
        "type": "video",
        "title": title,
        "author": author,
        "cover": cover,
        "images": [],
        "video_url": f"/api/proxy?url={requests.utils.quote(raw_play_url)}",
        "origin_url": raw_play_url
    }

def parse_twitter_x(url: str):
    """X (Twitter) 原生免秘钥 FixTweet 高清 4K 解析引擎"""
    match = re.search(r"(?:twitter\.com|x\.com)/(?:#!/)?(\w+)/status(?:es)?/(\d+)", url)
    if not match:
        return parse_via_ytdlp(url)

    user = match.group(1)
    status_id = match.group(2)
    api_url = f"https://api.fxtwitter.com/{user}/status/{status_id}"

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    try:
        r = requests.get(api_url, headers=headers, timeout=12)
        if r.status_code == 200:
            data = r.json()
            tweet = data.get("tweet")
            if tweet:
                text = tweet.get("text", "X (推特) 无水印媒体")
                author = tweet.get("author", {}).get("name", "X创作者")
                media = tweet.get("media", {})

                if media.get("videos"):
                    videos = media["videos"]
                    v = videos[0]
                    raw_play_url = v.get("url", "")
                    cover = v.get("thumbnail_url", "")
                    if raw_play_url:
                        return {
                            "type": "video",
                            "title": text[:60],
                            "author": author,
                            "cover": cover,
                            "images": [],
                            "video_url": f"/api/proxy?url={requests.utils.quote(raw_play_url)}",
                            "origin_url": raw_play_url
                        }

                if media.get("photos"):
                    photos = media["photos"]
                    imgs = [p.get("url") for p in photos if p.get("url")]
                    if imgs:
                        return {
                            "type": "image",
                            "title": text[:60],
                            "author": author,
                            "cover": imgs[0],
                            "images": imgs,
                            "video_url": "",
                            "origin_url": ""
                        }
    except Exception as e:
        print(f"[X-FixTweet-Error] {e}, fallback to yt-dlp")

    return parse_via_ytdlp(url)

def parse_tiktok(url: str):
    """TikTok 国际版无水印短视频提取，支持 tikwm 极速解析与官方 web 数据直读"""
    # 方式一：tikwm API (无需风控，秒级提取 1080P/720P 纯净无水印视频)
    try:
        r = requests.post("https://www.tikwm.com/api/", data={"url": url}, timeout=6).json()
        if r.get("code") == 0 and r.get("data"):
            d = r["data"]
            title = d.get("title") or "TikTok 视频"
            author = d.get("author", {}).get("nickname") or "TikTok 创作者"
            cover = d.get("cover") or ""
            play_url = d.get("play") or d.get("hdplay") or d.get("wmplay")
            if play_url:
                if play_url.startswith("/"):
                    play_url = "https://www.tikwm.com" + play_url
                return {
                    "type": "video",
                    "title": title,
                    "author": author,
                    "cover": cover,
                    "images": d.get("images") or [],
                    "video_url": f"/api/proxy?url={requests.utils.quote(play_url)}",
                    "origin_url": play_url
                }
    except Exception:
        pass

    # 方式二：直读移动端 / 网页端 HTML __UNIVERSAL_DATA_FOR_REHYDRATION__
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        }
        html = requests.get(url, headers=headers, allow_redirects=True, timeout=10).text
        m = re.search(r'id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>', html)
        if m:
            d = json.loads(m.group(1))
            item = d.get("__DEFAULT_SCOPE__", {}).get("webapp.video-detail", {}).get("itemInfo", {}).get("itemStruct", {})
            if item:
                title = item.get("desc") or "TikTok 视频"
                author = item.get("author", {}).get("nickname") or "TikTok 创作者"
                v = item.get("video", {})
                play_url = v.get("playAddr") or v.get("downloadAddr")
                cover = v.get("cover") or ""
                if play_url:
                    return {
                        "type": "video",
                        "title": title,
                        "author": author,
                        "cover": cover,
                        "images": [],
                        "video_url": f"/api/proxy?url={requests.utils.quote(play_url)}",
                        "origin_url": play_url
                    }
    except Exception:
        pass

    # 方式三：兜底转交给通用引擎
    return parse_via_ytdlp(url)

def parse_bilibili_mobile(bvid: str):
    """在公开视频信息接口受限时读取 B 站手机页面。"""
    headers = {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15",
        "Referer": "https://m.bilibili.com/",
    }
    response = requests.get(f"https://m.bilibili.com/video/{bvid}", headers=headers, timeout=15)
    if response.status_code != 200:
        raise ValueError(f"B站手机页面返回 HTTP {response.status_code}")
    html = response.text.replace(r"\u002F", "/").replace(r"\/", "/").replace(r"\u0026", "&")
    state = re.search(r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\});", html)
    title = "B站视频"
    cover = ""
    if state:
        try:
            data = json.loads(state.group(1))
            video_data = data.get("videoData") or {}
            title = video_data.get("title") or title
            cover = video_data.get("pic") or ""
        except (ValueError, AttributeError):
            pass
    links = re.findall(r'https?://[^"\s,<>]+?\.bilivideo\.c(?:om|n)[^"\s,<>]*', html)
    if not links:
        links = re.findall(r'https?://[^"\s,<>]+?\.mp4(?:\?[^"\s,<>]*)?', html)
    if not links:
        raise ValueError("B站手机页面可访问，但未找到可播放的视频文件")
    play_url = ""
    for link in dict.fromkeys(links[:6]):
        candidate = link.replace("&amp;", "&")
        probe = None
        try:
            probe = requests.get(
                candidate,
                headers={"User-Agent": headers["User-Agent"], "Referer": "https://m.bilibili.com/", "Range": "bytes=0-1"},
                timeout=8,
                stream=True,
            )
            if probe.status_code in (200, 206):
                play_url = candidate
                break
        except requests.RequestException:
            pass
        finally:
            if probe is not None:
                probe.close()
    if not play_url:
        raise ValueError("B站手机页面有视频地址，但媒体服务器拒绝下载")
    return {
        "type": "video",
        "title": title,
        "cover": cover,
        "images": [],
        "video_url": f"/api/proxy?url={requests.utils.quote(play_url)}",
        "origin_url": play_url,
    }


def get_bilibili_buvid():
    """动态获取或生成 B站合法 buvid3 / buvid4 设备指纹"""
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Referer": "https://www.bilibili.com/"
    }
    try:
        r = requests.get("https://api.bilibili.com/x/frontend/finger/spi", headers=headers, timeout=5)
        if r.status_code == 200:
            d = r.json().get("data", {})
            b3 = d.get("b_3")
            b4 = d.get("b_4")
            if b3:
                return b3, b4
    except Exception:
        pass
    
    # 备用随机算法生成标准格式
    u = str(secrets.token_hex(16)).upper()
    fake_b3 = f"{u[:8]}-{u[8:12]}-{u[12:16]}-{u[16:20]}-{u[20:]}{secrets.randbelow(89999)+10000}infoc"
    return fake_b3, ""

def parse_bilibili(url: str):
    """哔哩哔哩 (Bilibili) 官方接口解析引擎，带 buvid 指纹与防盗链中转"""
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Referer": "https://www.bilibili.com/",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        "X-Forwarded-For": "119.29.29.29",
        "X-Real-IP": "119.29.29.29",
        "Client-IP": "119.29.29.29",
        "Sec-Ch-Ua": '"Chromium";v="122", "Not(A:Brand";v="24", "Google Chrome";v="122"',
        "Sec-Ch-Ua-Mobile": "?0",
        "Sec-Ch-Ua-Platform": '"Windows"',
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-site"
    }
    
    target = url
    if "b23.tv" in url:
        try:
            r = requests.get(url, headers=headers, allow_redirects=True, timeout=10)
            target = r.url
        except Exception:
            pass

    # 优先检测 Bangumi 番剧/电影/电视剧 ep 或 ss 编号
    m_ep = re.search(r"ep(\d+)", target) or re.search(r"ep(\d+)", url)
    m_ss = re.search(r"ss(\d+)", target) or re.search(r"ss(\d+)", url)
    if "bangumi" in target or "bangumi" in url or m_ep or m_ss:
        pgc_param = f"ep_id={m_ep.group(1)}" if m_ep else f"season_id={m_ss.group(1)}"
        pgc_url = f"https://api.bilibili.com/pgc/view/web/season?{pgc_param}"
        try:
            pgc_res = requests.get(pgc_url, headers=headers, timeout=10).json()
            if pgc_res.get("code") == 0:
                pgc_data = pgc_res.get("result", {})
                title = pgc_data.get("title", "B站番剧")
                cover = pgc_data.get("cover", "")
                author = "哔哩哔哩番剧"
                episodes = pgc_data.get("episodes", [])
                ep_match = None
                if m_ep:
                    for e in episodes:
                        if str(e.get("ep_id")) == m_ep.group(1) or str(e.get("id")) == m_ep.group(1):
                            ep_match = e
                            break
                if not ep_match and episodes:
                    ep_match = episodes[0]

                if ep_match:
                    if ep_match.get("share_copy"):
                        title = ep_match.get("share_copy")
                    elif ep_match.get("show_title"):
                        title = f"{title} - {ep_match.get('show_title')}"
                    if ep_match.get("cover"):
                        cover = ep_match.get("cover")
                    cid = ep_match.get("cid")
                    bvid = ep_match.get("bvid")

                    # 调用番剧专属 playurl 接口 (带完整浏览器请求头)
                    pgc_play_headers = dict(headers)
                    pgc_play_headers["Referer"] = "https://www.bilibili.com/"
                    play_url_api = f"https://api.bilibili.com/pgc/player/web/playurl?bvid={bvid}&cid={cid}&qn=64&fnval=0&fnver=0&fourk=1"
                    p_res_raw = requests.get(play_url_api, headers=pgc_play_headers, timeout=10)
                    if p_res_raw.status_code == 200:
                        try:
                            p_res = p_res_raw.json()
                            durl = p_res.get("result", {}).get("durl", []) or p_res.get("data", {}).get("durl", [])
                            if durl and durl[0].get("url"):
                                stream_url = durl[0].get("url")
                                return {
                                    "type": "video",
                                    "title": title,
                                    "author": author,
                                    "cover": cover,
                                    "images": [],
                                    "video_url": f"/api/proxy?url={requests.utils.quote(stream_url)}",
                                    "origin_url": stream_url
                                }
                        except Exception:
                            pass

                    # 备用：常规 x/player/playurl 接口
                    if bvid and cid:
                        std_url = f"https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}&qn=64&fnval=1"
                        std_res_raw = requests.get(std_url, headers=pgc_play_headers, timeout=10)
                        if std_res_raw.status_code == 200:
                            try:
                                std_res = std_res_raw.json()
                                std_durl = std_res.get("data", {}).get("durl", [])
                                if std_durl and std_durl[0].get("url"):
                                    stream_url = std_durl[0].get("url")
                                    return {
                                        "type": "video",
                                        "title": title,
                                        "author": author,
                                        "cover": cover,
                                        "images": [],
                                        "video_url": f"/api/proxy?url={requests.utils.quote(stream_url)}",
                                        "origin_url": stream_url
                                    }
                            except Exception:
                                pass
        except Exception:
            pass

        # 原生番剧接口未能获取时，无缝切换至 yt-dlp 极速引擎解析番剧/电影
        try:
            return parse_via_ytdlp(url)
        except Exception:
            pass

    m = re.search(r"(BV[a-zA-Z0-9]+)", target) or re.search(r"(av\d+)", target, re.IGNORECASE)
    if not m:
        m = re.search(r"(BV[a-zA-Z0-9]+)", url) or re.search(r"(av\d+)", url, re.IGNORECASE)
    if not m:
        # BV/av 编号未检测到时，自动调用通用解析引擎兜底
        return parse_via_ytdlp(url)

    vid = m.group(1)
    param = f"bvid={vid}" if vid.upper().startswith("BV") else f"aid={vid[2:]}"
    headers["Referer"] = f"https://www.bilibili.com/video/{vid}/"

    b3, b4 = get_bilibili_buvid()
    cookies = {"buvid3": b3}
    if b4:
        cookies["buvid4"] = b4

    session = requests.Session()

    # 1. 查询视频基本信息与 CID
    view_url = f"https://api.bilibili.com/x/web-interface/view?{param}"
    try:
        view_res_raw = session.get(view_url, headers=headers, cookies=cookies, timeout=10)
    except Exception as e:
        raise ValueError(f"连接B站服务器超时: {str(e)}")

    if view_res_raw.status_code != 200:
        raise ValueError(f"B站接口响应异常 (HTTP {view_res_raw.status_code}): {view_res_raw.text[:100]}")

    try:
        view_res = view_res_raw.json()
    except Exception:
        raise ValueError(f"B站返回非JSON数据: {view_res_raw.text[:120]}")

    if view_res.get("code") != 0:
        raise ValueError(f"B站接口返回: {view_res.get('message', '获取信息失败')}")

    data = view_res.get("data", {})
    cid = data.get("cid")
    if not cid:
        raise ValueError("未能获取到B站视频 CID 信息")

    # 2. 查询无水印播放直链 (qn=64 是 720P，fnval=1 获取 mp4 格式直链)
    play_url = f"https://api.bilibili.com/x/player/playurl?{param}&cid={cid}&qn=64&fnval=1"
    try:
        play_res_raw = session.get(play_url, headers=headers, cookies=cookies, timeout=10)
    except Exception as e:
        raise ValueError(f"获取B站播放地址超时: {str(e)}")

    if play_res_raw.status_code != 200:
        raise ValueError(f"B站播放接口响应异常 (HTTP {play_res_raw.status_code}): {play_res_raw.text[:100]}")

    try:
        play_res = play_res_raw.json()
    except Exception:
        raise ValueError(f"B站播放接口返回非JSON数据: {play_res_raw.text[:120]}")

    durl = play_res.get("data", {}).get("durl", [])
    if not durl:
        raise ValueError("未能获取到B站视频播放直链，该视频可能需要大会员或登录")

    raw_play_url = durl[0].get("url", "")
    if not raw_play_url:
        raise ValueError("B站直链地址为空")

    cover_url = data.get("pic", "")
    if cover_url.startswith("http://"):
        cover_url = "https://" + cover_url[7:]
    elif cover_url.startswith("//"):
        cover_url = "https:" + cover_url

    return {
        "type": "video",
        "title": data.get("title", "B站视频"),
        "author": data.get("owner", {}).get("name", "B站创作者"),
        "cover": cover_url,
        "cover_url": cover_url,
        "images": [],
        "video_url": f"/api/proxy?url={requests.utils.quote(raw_play_url)}",
        "origin_url": raw_play_url
    }

def parse_jianying_jimeng(url: str):
    """剪映 / 即梦 (Jimeng / Jianying) 模板与作品无水印解析"""
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15"}
    target = url
    try:
        r = requests.get(url, headers=headers, allow_redirects=True, timeout=10)
        target = r.url
    except Exception:
        pass

    m = re.search(r"[?&](?:template_id|id)=(\d+)", target)
    if not m:
        m = re.search(r"(\d{15,20})", target) or re.search(r"(\d{15,20})", url)
    if not m:
        raise ValueError("未能提取剪映/即梦作品 ID，请检查链接")

    tid = m.group(1)
    a = 0
    n = int(datetime.datetime.now().timestamp())
    o = f"9e2c|mplates|{a}||{n}||11ac"
    import hashlib
    s = hashlib.md5(o.encode()).hexdigest()

    api_url = "https://lv-api.ulikecam.com/lv/v1/web/replicate/multi_get_templates"
    api_headers = {
        "sign": s,
        "pf": str(a),
        "sign-ver": "1",
        "device-time": str(n),
        "User-Agent": "Mozilla/5.0"
    }
    resp = requests.post(api_url, json={"sdk_version": "100.0.0", "id": [tid], "scene": "share"}, headers=api_headers, timeout=10).json()
    templates = resp.get("data", {}).get("templates", [])
    if not templates:
        raise ValueError("未找到该剪映/即梦作品或已被作者设为私密")

    t = templates[0]
    raw_video = t.get("video_url") or t.get("video_url_hd") or ""
    if not raw_video:
        raise ValueError("未能获取剪映/即梦视频播放直链")

    title = t.get("title") or t.get("desc") or "剪映/即梦精选作品"
    author = t.get("author", {}).get("name") or "创作者"
    cover = t.get("cover_url") or ""
    return {
        "type": "video",
        "title": title,
        "author": author,
        "cover": cover,
        "cover_url": cover,
        "images": [],
        "video_url": f"/api/proxy?url={requests.utils.quote(raw_video)}",
        "origin_url": raw_video
    }

def parse_toutiao(url: str):
    """今日头条 (Toutiao) 视频无水印解析"""
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15"}
    try:
        r = requests.get(url, headers=headers, allow_redirects=True, timeout=10)
        html = r.text
        m = re.search(r'(%7B%22sessionConfig%22[^<]+)', html)
        if m:
            import urllib.parse
            raw = urllib.parse.unquote(m.group(1))
            end = raw.rfind('}')
            data = json.loads(raw[:end+1])
            art = data.get("articleInfo", {})
            token = art.get("playAuthTokenV2")
            if token:
                import base64
                query = json.loads(base64.b64decode(token))["GetPlayInfoToken"]
                vod_res = requests.get("https://vod.bytedanceapi.com/?" + query, timeout=10).json()
                data_info = vod_res.get("Result", {}).get("Data", {})
                play_list = data_info.get("PlayInfoList", [])
                if play_list:
                    main_url = play_list[0].get("MainPlayUrl")
                    title = art.get("title") or "今日头条视频"
                    author = art.get("source") or art.get("user_name") or "头条创作者"
                    cover = data_info.get("CoverUrl") or art.get("posterUrl") or ""
                    return {
                        "type": "video",
                        "title": title,
                        "author": author,
                        "cover": cover,
                        "cover_url": cover,
                        "images": [],
                        "video_url": f"/api/proxy?url={requests.utils.quote(main_url)}",
                        "origin_url": main_url
                    }
    except Exception as e:
        print(f"[Toutiao-Native-Error] {e}, fallback to yt-dlp")

    return parse_via_ytdlp(url)

def parse_doubao(url: str):
    """豆包 (Doubao) AI 视频分享解析"""
    headers = {"User-Agent": "Mozilla/5.0"}
    m_vid = re.search(r"video_id=([a-zA-Z0-9_]+)", url)
    m_sid = re.search(r"share_id=([a-zA-Z0-9_]+)", url)
    if not m_vid:
        raise ValueError("未能从链接中提取豆包 video_id")
    api_url = "https://www.doubao.com/alice/media/bigmusic/get_video"
    payload = {"video_id": m_vid.group(1), "share_id": m_sid.group(1) if m_sid else ""}
    r = requests.post(api_url, json=payload, headers=headers, timeout=10).json()
    if r.get("code") != 0:
        raise ValueError(f"豆包接口返回: {r.get('msg', '获取视频失败')}")
    data = r.get("data", {})
    raw_video = data.get("url", "")
    if not raw_video:
        raise ValueError("豆包返回视频直链为空")
    return {
        "type": "video",
        "title": "豆包AI创作视频",
        "author": "豆包创作者",
        "cover": "",
        "cover_url": "",
        "images": [],
        "video_url": f"/api/proxy?url={requests.utils.quote(raw_video)}",
        "origin_url": raw_video
    }

def parse_fanqie_hongguo(url: str):
    """番茄小说 / 红果短剧 / 红果漫剧 解析"""
    headers = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15"}
    target = url
    try:
        r = requests.get(url, headers=headers, allow_redirects=True, timeout=10)
        target = r.url
    except Exception:
        pass

    m_vid = re.search(r"[?&]vid=(\d+)", target)
    m_video_id = re.search(r"[?&]video_id=(\d+)", target)
    target_id = ""
    if m_vid:
        target_id = m_vid.group(1)
    elif m_video_id:
        target_id = m_video_id.group(1)
    if not target_id:
        m_fallback = re.search(r"(\d{15,20})", target) or re.search(r"(\d{15,20})", url)
        if m_fallback:
            target_id = m_fallback.group(1)

    if not target_id:
        raise ValueError("无法提取番茄/红果短剧剧集编号")

    try:
        aweme_headers = {"User-Agent": "com.ss.android.ugc.aweme/110101 (Linux; U; Android 5.1.1; zh_CN; MI 9; Build/NMF26X; Cronet/58.0.2991.0)"}
        feed_url = f"https://api3-normal-c-hl.amemv.com/aweme/v1/feed/?aweme_id={target_id}"
        feed_res = requests.get(feed_url, headers=aweme_headers, timeout=10).json()
        aweme_list = feed_res.get("aweme_list", [])
        if aweme_list:
            item = aweme_list[0]
            video_obj = item.get("video", {})
            urls = video_obj.get("play_addr", {}).get("url_list", [])
            if urls:
                play_url = urls[0].replace("playwm", "play")
                cover_urls = video_obj.get("cover", {}).get("url_list", [])
                return {
                    "type": "video",
                    "title": item.get("desc") or "红果/番茄热门短剧",
                    "author": item.get("author", {}).get("nickname") or "短剧创作者",
                    "cover": cover_urls[0] if cover_urls else "",
                    "cover_url": cover_urls[0] if cover_urls else "",
                    "images": [],
                    "video_url": f"/api/proxy?url={requests.utils.quote(play_url)}",
                    "origin_url": play_url
                }
    except Exception as e:
        print(f"[Fanqie-Aweme-Feed-Error] {e}")

    fallback_url = f"https://hongguoduanju.com/video/public/{target_id}/360p.mp4"
    return {
        "type": "video",
        "title": "红果/番茄短剧集",
        "author": "短剧创作者",
        "cover": "",
        "cover_url": "",
        "images": [],
        "video_url": f"/api/proxy?url={requests.utils.quote(fallback_url)}",
        "origin_url": fallback_url
    }

def parse_via_ytdlp(url: str):
    """YouTube / TikTok / 通用国际媒体无水印极速提取引擎，支持 Deno 解密、Invidious 备用流与直链代理"""
    try:
        is_youtube = ("youtube.com" in url) or ("youtu.be" in url)

        # 查找服务器是否存在 Deno 运行时
        deno_path = shutil.which("deno")
        if not deno_path:
            for p in ["/usr/local/bin/deno", "/root/.deno/bin/deno"]:
                if os.path.exists(p):
                    deno_path = p
                    break

        # 检查服务器是否存在 cookies 授权文件
        cookie_file = None
        for cf in ["/root/youtube_cookies.txt", "/root/cookies.txt", "youtube_cookies.txt", "cookies.txt"]:
            if os.path.exists(cf) and os.path.getsize(cf) > 10:
                cookie_file = cf
                break

        info = None
        last_err = ""

        # 1. 优先尝试标准 yt-dlp 探测 (超时设为 12s 避免小程序端网络超时)
        cmd1 = [
            "yt-dlp",
            "--no-warnings",
            "-j",
            "--no-playlist",
            "--socket-timeout", "8",
            "--geo-bypass-country", "CN",
            "--add-header", "X-Forwarded-For: 119.29.29.29",
            "--add-header", "X-Real-IP: 119.29.29.29"
        ]
        if deno_path:
            cmd1.extend(["--js-runtimes", f"deno:{deno_path}"])
        if cookie_file:
            cmd1.extend(["--cookies", cookie_file])
        cmd1.append(url)

        try:
            res1 = subprocess.run(cmd1, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=12)
            if res1.returncode == 0 and res1.stdout.strip():
                info = json.loads(res1.stdout)
            else:
                last_err = res1.stderr.strip()
        except Exception as e:
            last_err = str(e)

        # 2. 如果是 YouTube 且初次失败，尝试备用公共 Invidious 快速解析直链 (仅需 1~2 秒，无需本地耗时合成)
        if is_youtube and not info:
            m_yt = re.search(r"(?:v=|\/|be\/|embed\/)([0-9A-Za-z_-]{11})", url)
            if m_yt:
                yt_id = m_yt.group(1)
                invidious_hosts = [
                    "https://yt.chocolatemoo53.com",
                    "https://inv.nadeko.net",
                    "https://invidious.nerdvpn.de"
                ]
                for host in invidious_hosts:
                    try:
                        inv_res = requests.get(f"{host}/api/v1/videos/{yt_id}?local=true", timeout=6)
                        if inv_res.status_code == 200:
                            inv_data = inv_res.json()
                            inv_title = inv_data.get("title", "YouTube 热门视频")
                            inv_author = inv_data.get("author", "YouTube 创作者")
                            inv_cover = ""
                            if inv_data.get("videoThumbnails"):
                                inv_cover = inv_data["videoThumbnails"][0].get("url", "")
                            if not inv_cover:
                                inv_cover = f"https://i.ytimg.com/vi/{yt_id}/hqdefault.jpg"

                            stream_url = None
                            # 优先选择合并音视频流
                            for f in inv_data.get("formatStreams", []):
                                if f.get("url"):
                                    stream_url = f.get("url")
                                    break
                            # 其次选择 MP4 视频流
                            if not stream_url:
                                for f in inv_data.get("adaptiveFormats", []):
                                    if "video/mp4" in f.get("type", "") and f.get("url"):
                                        stream_url = f.get("url")
                                        break

                            if stream_url:
                                return {
                                    "type": "video",
                                    "title": inv_title,
                                    "author": inv_author,
                                    "cover": inv_cover,
                                    "images": [],
                                    "video_url": f"/api/proxy?url={requests.utils.quote(stream_url)}",
                                    "origin_url": stream_url
                                }
                    except Exception:
                        continue

        # 3. 如果仍未获取到 info，尝试嵌入式客户端
        if is_youtube and not info:
            cmd2 = [
                "yt-dlp",
                "--no-warnings",
                "-j",
                "--no-playlist",
                "--extractor-args", "youtube:player_client=tv_embedded,web_embedded,mweb",
                "--socket-timeout", "8"
            ]
            if deno_path:
                cmd2.extend(["--js-runtimes", f"deno:{deno_path}"])
            if cookie_file:
                cmd2.extend(["--cookies", cookie_file])
            cmd2.append(url)
            try:
                res2 = subprocess.run(cmd2, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=12)
                if res2.returncode == 0 and res2.stdout.strip():
                    info = json.loads(res2.stdout)
                else:
                    if res2.stderr.strip():
                        last_err = res2.stderr.strip()
            except Exception as e:
                last_err = str(e)

        if not info:
            clean_err = re.sub(r"WARNING:[^\n]*", "", last_err).strip()
            clean_err = re.sub(r"Deprecated Feature:[^\n]*", "", clean_err).strip()
            lower_err = last_err.lower()
            if "geo restriction" in lower_err or "not available from your location" in lower_err or "not available in your region" in lower_err:
                raise ValueError("该内容为 B站 地区版权保护或大会员专享影视（仅限中国大陆地区播放），境外云端服务器受官方版权限制无法提取，请提取常规视频")
            if "Sign in to confirm you're not a bot" in last_err or "bot" in lower_err:
                raise ValueError("官方触发防机器人风控验证，请稍后再试")
            raise ValueError(f"解析失败: {clean_err[:150] or '上游接口响应超时，请重试'}")

        title = info.get("title", "无水印视频")
        author = info.get("uploader", "网络创作者")
        cover = info.get("thumbnail", "")

        # 寻址最佳可播放直链 (无需后台阻塞下载，由 proxy 流式分发，秒级返回)
        formats = info.get("formats", [])
        best_url = ""
        formats.reverse()
        for f in formats:
            if f.get("vcodec") != "none" and f.get("acodec") != "none" and f.get("url"):
                best_url = f.get("url")
                break

        if not best_url:
            for f in formats:
                if f.get("url") and "mp4" in f.get("ext", ""):
                    best_url = f.get("url")
                    break

        if not best_url:
            best_url = info.get("url", "")

        if not best_url:
            raise ValueError("未能提取到有效视频直链")

        return {
            "type": "video",
            "title": title,
            "author": author,
            "cover": cover,
            "images": [],
            "video_url": f"/api/proxy?url={requests.utils.quote(best_url)}",
            "origin_url": best_url
        }

    except Exception as e:
        raise ValueError(f"引擎执行失败: {str(e)}")


def parse_wechat_channels(url: str):
    """通过本机 2022 端口的视频号服务解析。"""
    try:
        response = requests.post(
            "http://127.0.0.1:2022/api/parse",
            json={"url": url},
            timeout=45,
        )
    except requests.RequestException as e:
        raise ValueError(f"视频号解析服务连接失败: {e}")

    if response.status_code != 200:
        raise ValueError(f"视频号解析服务异常 (HTTP {response.status_code})")

    try:
        payload = response.json()
    except ValueError:
        raise ValueError("视频号解析服务返回了无效数据")

    if payload.get("code") != 0:
        raise ValueError(payload.get("msg") or "视频号解析失败")

    data = payload.get("data") or {}
    media_url = data.get("h264_url") or data.get("video_url")
    if not media_url:
        raise ValueError("视频号解析结果为空，请更新元宝登录状态")

    proxy_path = "/api/wechat_proxy?url=" + requests.utils.quote(
        media_url, safe=""
    )
    decrypt_key = str(data.get("decrypt_key") or "")
    if decrypt_key and decrypt_key != "0":
        proxy_path += "&key=" + requests.utils.quote(
            decrypt_key, safe=""
        )

    cover_url = data.get("cover_url") or ""
    return {
        "type": "video",
        "title": data.get("title") or "视频号视频",
        "author": data.get("author") or "视频号创作者",
        "cover": cover_url,
        "cover_url": cover_url,
        "images": [],
        "video_url": proxy_path,
        "origin_url": proxy_path,
    }

class ParseRequest(BaseModel):
    url: Optional[str] = ""
    text: Optional[str] = ""
    user_id: Optional[str] = "guest"

class RedeemRequest(BaseModel):
    user_id: str
    card_key: str

class AdminLoginRequest(BaseModel):
    password: str

class GenerateCardRequest(BaseModel):
    card_type: str
    card_val: int
    count: int = 5

class AdjustUserRequest(BaseModel):
    user_id: str
    action: str
    value: int = 0

class FeedbackRequest(BaseModel):
    user_id: str = "guest"
    content: str
    contact: str = ""
    client_info: str = ""

class UserInfoRequest(BaseModel):
    user_id: str

def send_feedback_notifications(feedback_id: int, data: dict):
    """按环境变量配置发送邮件或企业微信群通知；失败不影响数据库记录。"""
    subject = f"一链取影新反馈 #{feedback_id}"
    body = (
        f"反馈编号：{feedback_id}\n"
        f"用户编号：{data.get('user_id', 'guest')}\n"
        f"联系方式：{data.get('contact') or '未填写'}\n"
        f"客户端：{data.get('client_info') or '未知'}\n\n"
        f"反馈内容：\n{data.get('content', '')}\n"
    )

    smtp_host = os.getenv("FEEDBACK_SMTP_HOST", "").strip()
    smtp_user = os.getenv("FEEDBACK_SMTP_USER", "").strip()
    smtp_password = os.getenv("FEEDBACK_SMTP_PASSWORD", "")
    email_to = os.getenv("FEEDBACK_EMAIL_TO", "sd0739@sd0739.top").strip()
    if smtp_host and smtp_user and smtp_password and email_to:
        try:
            smtp_port = int(os.getenv("FEEDBACK_SMTP_PORT", "465"))
            message = EmailMessage()
            message["Subject"] = subject
            message["From"] = smtp_user
            message["To"] = email_to
            message.set_content(body)
            if smtp_port == 465:
                with smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=15) as smtp:
                    smtp.login(smtp_user, smtp_password)
                    smtp.send_message(message)
            else:
                with smtplib.SMTP(smtp_host, smtp_port, timeout=15) as smtp:
                    smtp.starttls()
                    smtp.login(smtp_user, smtp_password)
                    smtp.send_message(message)
        except Exception as e:
            print(f"[feedback-email] send failed: {e}")

    webhook = os.getenv("FEEDBACK_WECOM_WEBHOOK", "").strip()
    if webhook.startswith("https://qyapi.weixin.qq.com/cgi-bin/webhook/send"):
        try:
            requests.post(
                webhook,
                json={"msgtype": "text", "text": {"content": subject + "\n" + body}},
                timeout=15,
            )
        except Exception as e:
            print(f"[feedback-wecom] send failed: {e}")

@app.get("/api/diag_bili")
def diag_bili(bvid: str = "BV1AF4g6MEX9"):
    res = {}
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Referer": f"https://www.bilibili.com/video/{bvid}/"
    }
    b3, b4 = get_bilibili_buvid()
    res["buvid3"] = b3
    res["buvid4"] = b4
    cookies = {"buvid3": b3}
    if b4: cookies["buvid4"] = b4

    try:
        r1 = requests.get(f"https://api.bilibili.com/x/web-interface/view?bvid={bvid}", headers=headers, cookies=cookies, timeout=5)
        res["view_code"] = r1.status_code
        res["view_text"] = r1.text[:200]
    except Exception as e:
        res["view_err"] = str(e)
    return res

@app.get("/api/diag_yt")
def diag_yt(id: str = "wE28u_nKjGU"):
    res = {}
    deno_path = shutil.which("deno")
    if not deno_path:
        for p in ["/usr/local/bin/deno", "/root/.deno/bin/deno"]:
            if os.path.exists(p):
                deno_path = p
                break
    res["deno_path"] = deno_path

    try:
        res["yt_version"] = subprocess.run(["yt-dlp", "--version"], capture_output=True, text=True).stdout.strip()
    except Exception as e:
        res["yt_version_err"] = str(e)

    cookie_file = None
    for cf in ["/root/youtube_cookies.txt", "/root/cookies.txt", "youtube_cookies.txt", "cookies.txt"]:
        if os.path.exists(cf) and os.path.getsize(cf) > 10:
            cookie_file = cf
            break
    res["cookie_file"] = cookie_file

    url = f"https://youtu.be/{id}"
    cmd = [
        "yt-dlp",
        "--no-warnings",
        "-j",
        "--no-playlist",
        "--socket-timeout", "8"
    ]
    if deno_path:
        cmd.extend(["--js-runtimes", f"deno:{deno_path}"])
    if cookie_file:
        cmd.extend(["--cookies", cookie_file])
    cmd.append(url)

    t0 = datetime.datetime.now()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=12)
        res["duration_sec"] = (datetime.datetime.now() - t0).total_seconds()
        res["code"] = p.returncode
        res["stdout_len"] = len(p.stdout)
        res["stderr"] = p.stderr[:300]
        if p.returncode == 0 and p.stdout.strip():
            info = json.loads(p.stdout)
            res["title"] = info.get("title")
            formats = info.get("formats", [])
            res["formats_count"] = len(formats)
            combined = [f.get("format_id") for f in formats if f.get("vcodec") != "none" and f.get("acodec") != "none"]
            res["combined_formats"] = combined
    except Exception as e:
        res["exec_err"] = str(e)
        res["duration_sec"] = (datetime.datetime.now() - t0).total_seconds()

    return res

@app.post("/api/parse")
def parse_video(req: ParseRequest):
    raw_text = req.url or req.text or ""
    urls = re.findall(r"https?://[a-zA-Z0-9.\-_]+(?::\d+)?(?:/[^\s]*)?", raw_text)
    if not urls:
        bv_match = re.search(r"(BV[a-zA-Z0-9]{10})", raw_text)
        if bv_match:
            urls = [f"https://www.bilibili.com/video/{bv_match.group(1)}"]
        else:
            raise HTTPException(status_code=400, detail="未检测到有效 HTTP/HTTPS 链接")
    target_url = urls[0]

    user = get_or_create_user(req.user_id)
    if user.get("is_banned"):
        raise HTTPException(status_code=403, detail="您的账号已被管理员禁用，如有疑问请联系客服")

    if not deduct_user_quota(req.user_id):
        raise HTTPException(status_code=403, detail="今日免费额度已用尽，请输入授权卡密兑换额度！")

    try:
        if "douyin.com" in target_url or "iesdouyin.com" in target_url:
            result = parse_douyin(target_url)
            platform = "抖音"
        elif "kuaishou.com" in target_url or "gifshow.com" in target_url:
            result = parse_kuaishou(target_url)
            platform = "快手"
        elif "xiaohongshu.com" in target_url or "xhslink.com" in target_url or "xhslink.cn" in target_url:
            result = parse_xiaohongshu(target_url)
            platform = "小红书"
        elif "bilibili.com" in target_url or "b23.tv" in target_url or "/BV" in target_url or "/bv" in target_url:
            try:
                result = parse_bilibili(target_url)
            except Exception:
                result = parse_via_ytdlp(target_url)
            platform = "B站"
        elif "ulikecam.com" in target_url or "jianying.com" in target_url:
            result = parse_jianying_jimeng(target_url)
            platform = "剪映/即梦"
        elif "toutiao.com" in target_url:
            result = parse_toutiao(target_url)
            platform = "今日头条"
        elif "doubao.com" in target_url:
            result = parse_doubao(target_url)
            platform = "豆包"
        elif "novelquickapp.com" in target_url or "changdunovel.com" in target_url or "fqnovel.com" in target_url:
            result = parse_fanqie_hongguo(target_url)
            platform = "番茄/红果短剧"
        elif "weixin.qq.com" in target_url or "channels.weixin.qq.com" in target_url:
            result = parse_wechat_channels(target_url)
            platform = "视频号"
        elif "twitter.com" in target_url or "x.com" in target_url:
            result = parse_twitter_x(target_url)
            platform = "X(推特)"
        elif "tiktok.com" in target_url:
            result = parse_tiktok(target_url)
            platform = "TikTok"
        elif "youtube.com" in target_url or "youtu.be" in target_url:
            result = parse_via_ytdlp(target_url)
            platform = "通用国际"
        else:
            result = parse_via_ytdlp(target_url)
            platform = "未知平台"

        conn = get_db()
        conn.execute(
            "INSERT INTO parse_logs (user_id, platform, url, title, created_at) VALUES (?, ?, ?, ?, ?)",
            (req.user_id, platform, target_url, result.get("title", "")[:80], datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        )
        conn.commit()
        conn.close()

        write_audit_log(
            "parse_success",
            req.user_id,
            f"平台={platform}；标题={result.get('title', '')[:120]}",
        )

        if "platform" not in result:
            result["platform"] = platform
        if "cover_url" not in result and "cover" in result:
            result["cover_url"] = result["cover"]

        return {
            "code": 0,
            "message": "解析成功",
            "data": result
        }
    except Exception as e:
        conn = get_db()
        conn.execute("UPDATE users SET daily_quota = daily_quota + 1 WHERE user_id = ?", (req.user_id,))
        conn.commit()
        conn.close()
        write_audit_log("parse_failed", req.user_id, f"原因={str(e)[:300]}")
        raise HTTPException(status_code=500, detail=f"解析失败: {str(e)}")

def build_user_info_response(user_id: str):
    user = get_or_create_user(user_id)
    if user.get("is_banned"):
        return {
            "code": 403,
            "message": "账号已被封禁",
            "data": {
                "user_id": user_id,
                "daily_quota": 0,
                "bonus_quota": 0,
                "total_quota": 0,
                "is_vip": False,
                "is_banned": True
            }
        }
    is_vip = bool(user["is_vip"])
    total_quota = 999999 if is_vip else int(user["daily_quota"] or 0) + int(user["bonus_quota"] or 0)
    return {
        "code": 0,
        "data": {
            "user_id": user["user_id"],
            "daily_quota": user["daily_quota"],
            "bonus_quota": user["bonus_quota"],
            "total_quota": total_quota,
            "is_vip": is_vip,
            "vip_expire_at": user["vip_expire_at"],
            "is_banned": bool(user.get("is_banned", 0))
        }
    }

@app.get("/api/user/info")
def get_user_info(user_id: str = Query(...)):
    return build_user_info_response(user_id)

@app.post("/api/user/info")
def post_user_info(req: UserInfoRequest):
    return build_user_info_response(req.user_id)

@app.post("/api/user/redeem")
def redeem_card(req: RedeemRequest):
    user = get_or_create_user(req.user_id)
    if user.get("is_banned"):
        raise HTTPException(status_code=403, detail="您的账号已被管理员禁用，无法兑换卡密")

    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT * FROM cards WHERE card_key = ?", (req.card_key.strip(),))
    card = cur.fetchone()

    if not card:
        conn.close()
        raise HTTPException(status_code=400, detail="卡密不存在，请仔细检查核对！")

    if card["is_used"] == 1:
        conn.close()
        raise HTTPException(status_code=400, detail=f"该卡密已于 {card['used_at']} 被使用！")

    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cur.execute("UPDATE cards SET is_used = 1, used_by = ?, used_at = ? WHERE card_key = ?", (req.user_id, now_str, req.card_key.strip()))

    card_type = card["card_type"]
    card_val = card["card_val"]
    tip_msg = ""

    if card_type == "quota":
        cur.execute("UPDATE users SET bonus_quota = bonus_quota + ? WHERE user_id = ?", (card_val, req.user_id))
        tip_msg = f"恭喜！成功增加 {card_val} 次不限期解析额度"
    elif card_type == "vip":
        if card_val >= 9999:
            expire_at = "2099-12-31 23:59:59"
            cur.execute("UPDATE users SET is_vip = 1, vip_expire_at = ? WHERE user_id = ?", (expire_at, req.user_id))
            tip_msg = "恭喜！已为您开通【尊贵永久 VIP 会员】，享无限次极速解析！"
        else:
            expire_at = (datetime.datetime.now() + datetime.timedelta(days=card_val)).strftime("%Y-%m-%d %H:%M:%S")
            cur.execute("UPDATE users SET is_vip = 1, vip_expire_at = ? WHERE user_id = ?", (expire_at, req.user_id))
            tip_msg = f"恭喜！已为您开通 {card_val} 天 VIP 会员，享无限次极速解析！"

    conn.commit()
    conn.close()
    safe_type = "增加次数" if card_type == "quota" else "开通VIP"
    safe_value = f"{card_val}次" if card_type == "quota" else ("永久" if card_val >= 9999 else f"{card_val}天")
    write_audit_log("redeem_card", req.user_id, f"{safe_type}；额度={safe_value}", actor="user")
    return {"code": 0, "message": tip_msg}

@app.post("/api/feedback")
def submit_feedback(req: FeedbackRequest, background_tasks: BackgroundTasks):
    content = (req.content or "").strip()
    contact = (req.contact or "").strip()
    client_info = (req.client_info or "").strip()
    if len(content) < 2:
        raise HTTPException(status_code=400, detail="请填写具体的问题或建议")
    if len(content) > 1000:
        raise HTTPException(status_code=400, detail="反馈内容不能超过1000字")
    if len(contact) > 100 or len(client_info) > 300:
        raise HTTPException(status_code=400, detail="反馈附加信息过长")

    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO feedback (user_id, content, contact, client_info, created_at) VALUES (?, ?, ?, ?, ?)",
        (req.user_id or "guest", content, contact, client_info, now_str),
    )
    feedback_id = cur.lastrowid
    conn.commit()
    conn.close()

    background_tasks.add_task(
        send_feedback_notifications,
        feedback_id,
        {
            "user_id": req.user_id or "guest",
            "content": content,
            "contact": contact,
            "client_info": client_info,
        },
    )
    return {"code": 0, "message": "感谢反馈，我们已经收到", "data": {"id": feedback_id}}

@app.get("/api/download_cached")
def download_cached_video(id: str = Query(...)):
    filename = f"{id}.mp4"
    filepath = os.path.join(VIDEO_CACHE_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="视频文件未生成或已被清理")
    return FileResponse(
        filepath,
        media_type="video/mp4",
        filename=filename,
        headers={"Accept-Ranges": "bytes"}
    )

@app.post("/api/image/inpaint")
async def repair_image(
    image: UploadFile = File(...),
    mask: str = Form(...),
):
    """按照小程序画布生成的矩形或画笔遮罩修复图片局部。"""
    try:
        import cv2
        import numpy as np
    except ImportError:
        raise HTTPException(status_code=503, detail="服务器尚未安装图片修复组件")

    allowed_types = {"image/jpeg", "image/png", "image/webp"}
    if image.content_type not in allowed_types:
        raise HTTPException(status_code=400, detail="仅支持 JPG、PNG 或 WebP 图片")

    raw = await image.read(15 * 1024 * 1024 + 1)
    if len(raw) > 15 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="图片不能超过 15MB")

    source = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_COLOR)
    if source is None:
        raise HTTPException(status_code=400, detail="无法读取图片文件")
    height, width = source.shape[:2]
    if width * height > 36_000_000:
        raise HTTPException(status_code=413, detail="图片分辨率过高，请先压缩后重试")

    try:
        spec = json.loads(mask)
        canvas_width = float(spec["canvasWidth"])
        canvas_height = float(spec["canvasHeight"])
        image_rect = spec["imageRect"]
        actions = spec["actions"]
    except (ValueError, TypeError, KeyError):
        raise HTTPException(status_code=400, detail="修复区域数据格式错误")

    if canvas_width <= 0 or canvas_height <= 0 or not actions:
        raise HTTPException(status_code=400, detail="请先框选或涂抹需要修复的区域")

    rx = float(image_rect.get("x", 0))
    ry = float(image_rect.get("y", 0))
    rw = float(image_rect.get("w", 0))
    rh = float(image_rect.get("h", 0))
    if rw <= 0 or rh <= 0:
        raise HTTPException(status_code=400, detail="图片显示区域无效")

    scale_x = width / rw
    scale_y = height / rh
    repair_mask = np.zeros((height, width), dtype=np.uint8)

    def map_point(x, y):
        px = int(round((float(x) - rx) * scale_x))
        py = int(round((float(y) - ry) * scale_y))
        return max(0, min(width - 1, px)), max(0, min(height - 1, py))

    for action in actions[:200]:
        kind = action.get("type")
        if kind == "rect":
            x1, y1 = map_point(action.get("x", 0), action.get("y", 0))
            x2, y2 = map_point(
                float(action.get("x", 0)) + float(action.get("w", 0)),
                float(action.get("y", 0)) + float(action.get("h", 0)),
            )
            left, right = sorted((x1, x2))
            top, bottom = sorted((y1, y2))
            if right - left >= 2 and bottom - top >= 2:
                cv2.rectangle(repair_mask, (left, top), (right, bottom), 255, -1)
        elif kind == "stroke":
            points = action.get("points") or []
            mapped = [map_point(p.get("x", 0), p.get("y", 0)) for p in points[:2000]]
            thickness = max(3, int(float(action.get("size", 20)) * (scale_x + scale_y) / 2))
            if len(mapped) == 1:
                cv2.circle(repair_mask, mapped[0], max(2, thickness // 2), 255, -1)
            elif len(mapped) > 1:
                cv2.polylines(
                    repair_mask,
                    [np.array(mapped, dtype=np.int32)],
                    False,
                    255,
                    thickness,
                    lineType=cv2.LINE_AA,
                )

    if cv2.countNonZero(repair_mask) == 0:
        raise HTTPException(status_code=400, detail="修复区域为空")

    repaired = cv2.inpaint(source, repair_mask, 5, cv2.INPAINT_TELEA)
    result_id = uuid.uuid4().hex
    result_path = os.path.join(IMAGE_REPAIR_DIR, f"{result_id}.jpg")
    if not cv2.imwrite(result_path, repaired, [cv2.IMWRITE_JPEG_QUALITY, 94]):
        raise HTTPException(status_code=500, detail="修复结果保存失败")

    # 顺便清理一天前的临时结果。
    cutoff = time.time() - 86400
    try:
        for name in os.listdir(IMAGE_REPAIR_DIR):
            path = os.path.join(IMAGE_REPAIR_DIR, name)
            if os.path.isfile(path) and os.path.getmtime(path) < cutoff:
                os.remove(path)
    except OSError:
        pass

    return {
        "code": 0,
        "message": "图片修复完成",
        "data": {"url": f"/api/image/result?id={result_id}"},
    }

@app.get("/api/image/result")
def get_repaired_image(id: str = Query(..., regex=r"^[a-f0-9]{32}$")):
    path = os.path.join(IMAGE_REPAIR_DIR, f"{id}.jpg")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="图片结果不存在或已过期")
    return FileResponse(
        path,
        media_type="image/jpeg",
        filename="repaired-image.jpg",
        headers={"Cache-Control": "private, max-age=86400"},
    )

@app.get("/api/proxy")
def proxy_stream(
    request: Request,
    url: str = Query(..., description="目标媒体直链"),
    download: int = Query(0, description="是否作为附件下载"),
):
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        }

        # 核心：透传客户端 Range 请求头，若无则自动注入 bytes=0-，防止被 EdgeOne/防盗链 WAF 识别为爬虫拦截（返回 567）
        client_range = request.headers.get("range")
        if client_range:
            headers["Range"] = client_range
        elif "bilivideo" in url or "upgcxcode" in url or "bilibili" in url:
            headers["Range"] = "bytes=0-"

        if "bilivideo" in url or "upgcxcode" in url or "bilibili" in url:
            headers["Referer"] = "https://www.bilibili.com/"
            headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        elif "xhscdn" in url or "xiaohongshu" in url:
            headers["Referer"] = "https://www.xiaohongshu.com/"
            headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15"
        elif "kuaishou" in url or "gifshow" in url:
            headers["Referer"] = "https://www.kuaishou.com/"
            headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15"
        elif "tiktok" in url or "byteoversea" in url:
            headers["Referer"] = "https://www.tiktok.com/"
        elif "googlevideo" in url or "youtube" in url:
            headers["Referer"] = "https://www.youtube.com/"
        elif "twimg" in url or "twitter" in url or "x.com" in url:
            headers["Referer"] = "https://x.com/"
        elif any(d in url for d in ["365yg", "vlabvod", "toutiaovod", "fqnovel", "qznovel", "hongguoduanju"]):
            headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        else:
            headers["Referer"] = "https://www.douyin.com/"
            headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15"

        r = requests.get(url, headers=headers, stream=True, timeout=45)
        
        if r.status_code not in [200, 206]:
            raise HTTPException(status_code=r.status_code, detail="上游视频源防盗链拦截或直链失效")
        
        ctype = r.headers.get("content-type", "")
        if "text/plain" in ctype or "text/html" in ctype:
            raise HTTPException(status_code=502, detail="上游视频源返回了错误页面，非媒体数据")

        disposition = "attachment" if download else "inline"
        resp_headers = {
            "Content-Disposition": f'{disposition}; filename="video.mp4"',
            "Accept-Ranges": "bytes"
        }
        if "content-length" in r.headers:
            resp_headers["Content-Length"] = r.headers["content-length"]
        if "content-range" in r.headers:
            resp_headers["Content-Range"] = r.headers["content-range"]

        # 小程序 downloadFile 整体下载时使用 200 响应以保证保存成功；客户端分段请求时透传 206
        status_code = 206 if (client_range and r.status_code == 206) else 200

        return StreamingResponse(
            r.iter_content(chunk_size=1024 * 512),
            status_code=status_code,
            media_type=ctype or "video/mp4",
            headers=resp_headers
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"视频中转串流失败: {str(e)}")


@app.get("/api/wechat_proxy")
def wechat_proxy_stream(
    request: Request,
    url: str = Query(..., description="视频号媒体地址"),
    key: str = Query("", description="视频号媒体解密参数"),
    download: int = Query(0, description="是否作为附件下载"),
):
    parsed = urlparse(url)
    hostname = (parsed.hostname or "").lower()

    # 只允许腾讯 HTTPS 媒体地址，防止代理任意地址。
    if parsed.scheme != "https" or not hostname.endswith(".qq.com"):
        raise HTTPException(
            status_code=400,
            detail="视频号媒体地址不合法"
        )

    request_headers = {}
    if request.headers.get("range"):
        request_headers["Range"] = request.headers["range"]

    try:
        upstream = requests.get(
            "http://127.0.0.1:2022/api/proxy",
            params={"url": url, "key": key},
            headers=request_headers,
            stream=True,
            timeout=60,
        )
    except requests.RequestException as e:
        raise HTTPException(
            status_code=502,
            detail=f"视频号媒体服务连接失败: {e}"
        )

    if upstream.status_code not in (200, 206):
        upstream.close()
        raise HTTPException(
            status_code=502,
            detail="视频号媒体地址已失效，请重新解析"
        )

    disposition = "attachment" if download else "inline"
    response_headers = {
        "Content-Disposition": f'{disposition}; filename="wechat-video.mp4"',
        "Accept-Ranges": upstream.headers.get(
            "Accept-Ranges", "bytes"
        ),
    }
    for name in ("Content-Length", "Content-Range"):
        if upstream.headers.get(name):
            response_headers[name] = upstream.headers[name]

    def stream_media():
        try:
            yield from upstream.iter_content(
                chunk_size=512 * 1024
            )
        finally:
            upstream.close()

    return StreamingResponse(
        stream_media(),
        status_code=upstream.status_code,
        media_type=upstream.headers.get(
            "Content-Type", "video/mp4"
        ),
        headers=response_headers,
    )

@app.post("/api/admin/login")
def admin_login(req: AdminLoginRequest):
    if req.password == ADMIN_PASSWORD:
        return {"code": 0, "token": secrets.token_hex(16)}
    return {"code": 1, "message": "管理员密码错误"}

@app.get("/api/admin/data")
def admin_get_data(token: str = Query(...)):
    conn = get_db()
    users = conn.execute("SELECT * FROM users ORDER BY created_at DESC").fetchall()
    cards = conn.execute("SELECT * FROM cards ORDER BY created_at DESC LIMIT 200").fetchall()
    logs = conn.execute("SELECT * FROM parse_logs ORDER BY created_at DESC LIMIT 100").fetchall()
    feedback = conn.execute("SELECT * FROM feedback ORDER BY created_at DESC LIMIT 200").fetchall()
    audit_logs = conn.execute("SELECT * FROM audit_logs ORDER BY id DESC LIMIT 500").fetchall()
    conn.close()
    return {
        "code": 0,
        "users": [dict(u) for u in users],
        "cards": [dict(c) for c in cards],
        "logs": [dict(l) for l in logs],
        "feedback": [dict(item) for item in feedback],
        "audit_logs": [dict(item) for item in audit_logs]
    }

@app.post("/api/admin/generate_cards")
def admin_generate_cards(req: GenerateCardRequest):
    conn = get_db()
    now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    new_keys = []
    prefix = "VIP" if req.card_type == "vip" else "ADD"
    for _ in range(req.count):
        token = secrets.token_hex(4).upper()
        token2 = secrets.token_hex(4).upper()
        key = f"{prefix}50-{token}-{token2}"
        new_keys.append(key)
        conn.execute(
            "INSERT INTO cards (card_key, card_type, card_val, is_used, created_at) VALUES (?, ?, ?, 0, ?)",
            (key, req.card_type, req.card_val, now_str)
        )
    conn.commit()
    conn.close()
    return {"code": 0, "keys": new_keys}

@app.post("/api/admin/adjust_user")
def admin_adjust_user(req: AdjustUserRequest):
    conn = get_db()
    detail = ""
    if req.action == "add_quota":
        conn.execute("UPDATE users SET bonus_quota = bonus_quota + ? WHERE user_id = ?", (req.value, req.user_id))
        detail = f"增加额外次数 +{req.value}"
    elif req.action == "sub_quota":
        conn.execute("UPDATE users SET bonus_quota = MAX(0, bonus_quota - ?) WHERE user_id = ?", (req.value, req.user_id))
        detail = f"减少额外次数 -{req.value}"
    elif req.action == "set_quota":
        conn.execute("UPDATE users SET bonus_quota = ? WHERE user_id = ?", (max(0, req.value), req.user_id))
        detail = f"设置额外次数为 {max(0, req.value)}"
    elif req.action == "set_vip":
        expire = "2099-12-31 23:59:59" if req.value >= 9999 else (datetime.datetime.now() + datetime.timedelta(days=req.value)).strftime("%Y-%m-%d %H:%M:%S")
        conn.execute("UPDATE users SET is_vip = 1, vip_expire_at = ? WHERE user_id = ?", (expire, req.user_id))
        detail = "开通永久VIP" if req.value >= 9999 else f"开通VIP {req.value}天"
    elif req.action == "cancel_vip":
        conn.execute("UPDATE users SET is_vip = 0, vip_expire_at = NULL WHERE user_id = ?", (req.user_id,))
        detail = "取消VIP"
    elif req.action == "ban_user":
        conn.execute("UPDATE users SET is_banned = 1 WHERE user_id = ?", (req.user_id,))
        detail = "禁用用户"
    elif req.action == "unban_user":
        conn.execute("UPDATE users SET is_banned = 0 WHERE user_id = ?", (req.user_id,))
        detail = "解除禁用"
    elif req.action == "reset":
        conn.execute("UPDATE users SET daily_quota = 10, bonus_quota = 0, is_vip = 0, is_banned = 0 WHERE user_id = ?", (req.user_id,))
        detail = "重置用户状态和次数"
    else:
        conn.close()
        raise HTTPException(status_code=400, detail="不支持的用户操作")
    conn.commit()
    conn.close()
    write_audit_log(req.action, req.user_id, detail, actor="admin")
    return {"code": 0, "message": "用户状态已更新"}

# ----------------- 钞机汇玩 · 现代极简双栏后台 -----------------
@app.get("/admin", response_class=HTMLResponse)
def admin_dashboard_page():
    return """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>钞机汇玩 · 运营管理后台</title>
    <!-- Tailwind CSS (国内极速 CDN) -->
    <script src="https://cdn.tailwindcss.com"></script>
    <!-- Font Awesome 图标库 (BootCDN 国内节点) -->
    <link rel="stylesheet" href="https://cdn.bootcdn.net/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <!-- Vue 3 (优先 BootCDN 国内极速节点，饿了么 CDN 兜底) -->
    <script src="https://cdn.bootcdn.net/ajax/libs/vue/3.3.4/vue.global.prod.min.js"></script>
    <script>
        if (!window.Vue) {
            document.write('<script src="https://npm.elemecdn.com/vue@3.3.4/dist/vue.global.prod.js"><\\/script>');
        }
    </script>
    <style>
        /* no v-cloak */
        body { font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Segoe UI", Roboto, sans-serif; }
        .sidebar-item-active { background-color: #fee2e2; color: #dc2626; font-weight: 600; }
        .sidebar-item-active i { color: #dc2626; }
    </style>
</head>
<body class="bg-[#f8f9fa] text-gray-800 antialiased min-h-screen">
    <div id="app" class="flex min-h-screen">
        <!-- 登录弹窗 (未登录时居中覆盖展示) -->
        <div v-if="!token" class="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
            <div class="bg-white w-full max-w-sm rounded-3xl p-8 shadow-2xl border border-gray-100">
                <div class="flex items-center space-x-3.5 mb-6">
                    <div class="w-11 h-11 bg-gradient-to-tr from-amber-500 to-rose-600 text-white rounded-2xl flex items-center justify-center text-xl font-black shadow-md shadow-rose-200">
                        钞
                    </div>
                    <div>
                        <h2 class="text-base font-bold text-gray-900 tracking-tight">钞机汇玩</h2>
                        <p class="text-xs text-gray-400">运营管理后台</p>
                    </div>
                </div>
                <form @submit.prevent="handleLogin" class="space-y-4">
                    <div>
                        <label class="block text-xs font-semibold text-gray-500 mb-1.5">管理密码</label>
                        <input id="pwd-input" type="password" v-model="loginPwd" autofocus placeholder="请输入管理员登录密码"
                               class="w-full px-4 py-2.5 text-sm bg-gray-50 border border-gray-200 rounded-xl focus:bg-white focus:outline-none focus:ring-2 focus:ring-rose-400 transition">
                    </div>
                    <div v-if="loginErr" class="text-xs text-rose-500 font-medium bg-rose-50 p-2 rounded-lg flex items-center space-x-1.5">
                        <i class="fa-solid fa-circle-exclamation"></i>
                        <span>{{ loginErr }}</span>
                    </div>
                    <button id="login-btn" type="submit" :disabled="loggingIn"
                            class="w-full py-2.5 bg-gradient-to-r from-rose-500 to-rose-600 hover:from-rose-600 hover:to-rose-700 text-white text-sm font-semibold rounded-xl transition shadow-md shadow-rose-200 cursor-pointer disabled:opacity-60">
                        {{ loggingIn ? '安全验证中...' : '登 录' }}
                    </button>
                </form>
            </div>
        </div>

        <!-- 1. 左侧 Sidebar 导航栏 -->
        <aside class="w-64 bg-white border-r border-gray-100 flex flex-col justify-between py-6 px-4 shrink-0 shadow-sm">
            <div>
                <!-- Logo 区 -->
                <div class="flex items-center space-x-3 px-3 mb-8">
                    <div class="w-10 h-10 bg-gradient-to-tr from-amber-500 to-rose-600 text-white rounded-xl flex items-center justify-center text-lg font-bold shadow-md shadow-rose-200">
                        钞
                    </div>
                    <div>
                        <h1 class="text-sm font-bold text-gray-900 tracking-tight">钞机汇玩</h1>
                        <p class="text-[11px] text-gray-400">运营管理后台</p>
                    </div>
                </div>

                <!-- 导航组 -->
                <div class="text-[11px] font-semibold text-gray-400 px-3 mb-2 uppercase tracking-wider">工作台</div>
                <nav class="space-y-1">
                    <button @click="currentTab = 'overview'" 
                            :class="currentTab === 'overview' ? 'sidebar-item-active' : 'text-gray-600 hover:bg-gray-50'"
                            class="w-full flex items-center justify-between px-3 py-2.5 rounded-xl text-sm transition">
                        <div class="flex items-center space-x-3">
                            <i class="fa-solid fa-chart-pie w-4 text-gray-400"></i>
                            <span>运营概览</span>
                        </div>
                    </button>

                    <button @click="currentTab = 'cards'" 
                            :class="currentTab === 'cards' ? 'sidebar-item-active' : 'text-gray-600 hover:bg-gray-50'"
                            class="w-full flex items-center justify-between px-3 py-2.5 rounded-xl text-sm transition">
                        <div class="flex items-center space-x-3">
                            <i class="fa-solid fa-ticket w-4 text-gray-400"></i>
                            <span>卡密与授权</span>
                        </div>
                        <span v-if="unusedCardsCount > 0" class="text-[10px] bg-red-100 text-red-600 font-bold px-2 py-0.5 rounded-full">{{ unusedCardsCount }}</span>
                    </button>

                    <button @click="currentTab = 'users'" 
                            :class="currentTab === 'users' ? 'sidebar-item-active' : 'text-gray-600 hover:bg-gray-50'"
                            class="w-full flex items-center justify-between px-3 py-2.5 rounded-xl text-sm transition">
                        <div class="flex items-center space-x-3">
                            <i class="fa-solid fa-users w-4 text-gray-400"></i>
                            <span>用户与会员</span>
                        </div>
                        <span class="text-[10px] text-gray-400 font-medium">{{ users.length }}</span>
                    </button>

                    <button @click="currentTab = 'services'" 
                            :class="currentTab === 'services' ? 'sidebar-item-active' : 'text-gray-600 hover:bg-gray-50'"
                            class="w-full flex items-center justify-between px-3 py-2.5 rounded-xl text-sm transition">
                        <div class="flex items-center space-x-3">
                            <i class="fa-solid fa-server w-4 text-gray-400"></i>
                            <span>服务监控</span>
                        </div>
                        <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
                    </button>

                    <button @click="currentTab = 'audit'"
                            :class="currentTab === 'audit' ? 'sidebar-item-active' : 'text-gray-600 hover:bg-gray-50'"
                            class="w-full flex items-center justify-between px-3 py-2.5 rounded-xl text-sm transition">
                        <div class="flex items-center space-x-3">
                            <i class="fa-solid fa-clock-rotate-left w-4 text-gray-400"></i>
                            <span>操作日志</span>
                        </div>
                        <span class="text-[10px] text-gray-400 font-medium">{{ auditLogs.length }}</span>
                    </button>

                    <button @click="currentTab = 'settings'" 
                            :class="currentTab === 'settings' ? 'sidebar-item-active' : 'text-gray-600 hover:bg-gray-50'"
                            class="w-full flex items-center justify-between px-3 py-2.5 rounded-xl text-sm transition">
                        <div class="flex items-center space-x-3">
                            <i class="fa-solid fa-gear w-4 text-gray-400"></i>
                            <span>系统设置</span>
                        </div>
                    </button>
                </nav>
            </div>

            <!-- 底部安全提示与退出 -->
            <div class="border-t border-gray-100 pt-4 px-2">
                <div class="flex items-center space-x-2 text-xs text-gray-400 mb-3">
                    <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
                    <span>安全远程访问 · SSL加密</span>
                </div>
                <button @click="logout" class="text-xs text-gray-400 hover:text-red-500 flex items-center space-x-2 transition cursor-pointer">
                    <i class="fa-solid fa-arrow-right-from-bracket"></i>
                    <span>安全登出</span>
                </button>
            </div>
        </aside>

        <!-- 2. 右侧主体工作区 -->
        <main class="flex-1 p-8 overflow-y-auto max-w-7xl">
            <!-- 顶部 Header 状态 -->
            <div class="flex items-center justify-between mb-8 pb-4 border-b border-gray-200/60">
                <div>
                    <div class="text-xs text-gray-400 mb-1">
                        钞机汇玩 / 管理后台 / 
                        <span class="text-gray-700 font-semibold">
                            {{ tabName }}
                        </span>
                    </div>
                    <h2 class="text-xl font-bold text-gray-900 tracking-tight">
                        {{ tabTitle }}
                    </h2>
                </div>
                <div class="flex items-center space-x-4">
                    <span class="text-xs text-gray-400">更新于 {{ lastUpdatedTime }}</span>
                    <button @click="loadData" class="px-3.5 py-1.5 bg-white border border-gray-200 hover:bg-gray-50 text-xs font-semibold rounded-xl text-gray-700 shadow-sm flex items-center space-x-1.5 transition cursor-pointer">
                        <i class="fa-solid fa-rotate-right text-gray-400"></i>
                        <span>刷新数据</span>
                    </button>
                </div>
            </div>

            <!-- TAB 1: 卡密与授权 -->
            <div v-if="currentTab === 'cards'" class="space-y-6">
                <!-- 生成卡密快捷操作卡片 -->
                <div class="bg-white rounded-2xl p-6 border border-gray-100 shadow-sm">
                    <div class="mb-4">
                        <h3 class="text-sm font-bold text-gray-900">批量生成授权卡密</h3>
                        <p class="text-xs text-gray-400 mt-0.5">生成的卡密可直接发放给客户或在发卡平台销售，用户在【钞机汇玩】小程序内输入即可秒级兑换。</p>
                    </div>

                    <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-3">
                        <div>
                            <label class="block text-xs font-medium text-gray-500 mb-1.5">卡密权益类型</label>
                            <select v-model="genType" class="w-full text-xs px-3.5 py-2.5 bg-gray-50 border border-gray-200 rounded-xl focus:bg-white focus:outline-none">
                                <option value="quota_50">增加 50 次解析额度</option>
                                <option value="quota_100">增加 100 次解析额度</option>
                                <option value="quota_500">增加 500 次解析额度</option>
                                <option value="vip_30">开通 30 天 VIP 会员</option>
                                <option value="vip_permanent">开通【永久 VIP 会员】</option>
                            </select>
                        </div>
                        <div>
                            <label class="block text-xs font-medium text-gray-500 mb-1.5">生成张数</label>
                            <input type="number" v-model.number="genCount" min="1" max="100" class="w-full text-xs px-3.5 py-2 bg-gray-50 border border-gray-200 rounded-xl focus:bg-white focus:outline-none">
                        </div>
                        <div class="flex items-end">
                            <button @click="handleGenerateCards" class="w-full py-2.5 bg-gradient-to-r from-rose-500 to-rose-600 hover:from-rose-600 hover:to-rose-700 text-white text-xs font-semibold rounded-xl transition shadow-md shadow-rose-100 cursor-pointer">
                                立即生成授权码
                            </button>
                        </div>
                    </div>

                    <!-- 刚生成的卡密展示 -->
                    <div v-if="newGeneratedKeys.length > 0" class="bg-rose-50/60 border border-rose-100 rounded-2xl p-4 mt-4">
                        <div class="flex items-center justify-between mb-2.5">
                            <span class="text-xs font-bold text-rose-800">最新生成卡密 (共 {{ newGeneratedKeys.length }} 张)</span>
                            <button @click="copyAllKeys" class="text-xs text-rose-600 hover:underline font-semibold cursor-pointer">一键复制全部</button>
                        </div>
                        <div class="font-mono text-xs text-rose-900 bg-white p-3 rounded-xl border border-rose-100 max-h-36 overflow-y-auto space-y-1.5">
                            <div v-for="k in newGeneratedKeys" :key="k" class="flex justify-between items-center hover:bg-rose-50/50 px-2 py-1 rounded-lg">
                                <span>{{ k }}</span>
                                <button @click="copyText(k)" class="text-[11px] text-gray-400 hover:text-rose-600 cursor-pointer">复制</button>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- 卡密数据表格 -->
                <div class="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
                    <div class="p-5 border-b border-gray-100 flex items-center justify-between">
                        <div>
                            <h3 class="text-sm font-bold text-gray-900">授权卡密流水 (最近 200 张)</h3>
                            <p class="text-xs text-gray-400 mt-0.5">实时核销状态与使用者追踪</p>
                        </div>
                        <input type="text" v-model="searchCard" placeholder="过滤卡密或使用者..." 
                               class="px-3.5 py-1.5 text-xs bg-gray-50 border border-gray-200 rounded-xl w-52 focus:bg-white focus:outline-none">
                    </div>
                    <div class="overflow-x-auto">
                        <table class="w-full text-left text-xs">
                            <thead class="bg-gray-50/70 border-b border-gray-100 text-gray-400 font-semibold uppercase">
                                <tr>
                                    <th class="py-3.5 px-4">卡密兑换码</th>
                                    <th class="py-3.5 px-4">权益属性</th>
                                    <th class="py-3.5 px-4">使用状态</th>
                                    <th class="py-3.5 px-4">使用者 ID</th>
                                    <th class="py-3.5 px-4">使用时间</th>
                                    <th class="py-3.5 px-4 text-right">操作</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-100">
                                <tr v-for="c in filteredCards" :key="c.card_key" class="hover:bg-gray-50/60 transition">
                                    <td class="py-3.5 px-4 font-mono font-bold text-gray-800">{{ c.card_key }}</td>
                                    <td class="py-3.5 px-4">
                                        <span v-if="c.card_type === 'vip'" class="px-2.5 py-0.5 text-[11px] bg-purple-50 text-purple-700 rounded-md font-semibold">
                                            👑 {{ c.card_val >= 9999 ? '永久 VIP' : c.card_val + '天 VIP' }}
                                        </span>
                                        <span v-else class="px-2.5 py-0.5 text-[11px] bg-emerald-50 text-emerald-700 rounded-md font-semibold">
                                            +{{ c.card_val }} 次解析额度
                                        </span>
                                    </td>
                                    <td class="py-3.5 px-4">
                                        <span v-if="c.is_used" class="px-2 py-0.5 text-[11px] bg-gray-100 text-gray-500 rounded-md">已使用</span>
                                        <span v-else class="px-2 py-0.5 text-[11px] bg-emerald-100 text-emerald-800 rounded-md font-semibold">未使用</span>
                                    </td>
                                    <td class="py-3.5 px-4 font-mono text-gray-500">{{ c.used_by || '-' }}</td>
                                    <td class="py-3.5 px-4 text-gray-400">{{ c.used_at || '-' }}</td>
                                    <td class="py-3.5 px-4 text-right">
                                        <button @click="copyText(c.card_key)" class="text-rose-600 hover:underline cursor-pointer">复制</button>
                                    </td>
                                </tr>
                                <tr v-if="filteredCards.length === 0">
                                    <td colspan="6" class="py-12 text-center text-gray-400">暂无匹配卡密记录</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <!-- TAB 2: 用户与会员 -->
            <div v-if="currentTab === 'users'" class="space-y-6">
                <div class="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
                    <div class="p-5 border-b border-gray-100 flex items-center justify-between">
                        <div>
                            <h3 class="text-sm font-bold text-gray-900">用户与会员中心</h3>
                            <p class="text-xs text-gray-400 mt-0.5">管理【钞机汇玩】全部客户端用户，支持直接加减额度、封禁/解封与开通VIP</p>
                        </div>
                        <input type="text" v-model="searchUser" placeholder="搜索用户 ID..." 
                               class="px-3.5 py-1.5 text-xs bg-gray-50 border border-gray-200 rounded-xl w-52 focus:bg-white focus:outline-none">
                    </div>
                    <div class="overflow-x-auto">
                        <table class="w-full text-left text-xs">
                            <thead class="bg-gray-50/70 border-b border-gray-100 text-gray-400 font-semibold uppercase">
                                <tr>
                                    <th class="py-3.5 px-4">用户 ID</th>
                                    <th class="py-3.5 px-4">今日免费剩余</th>
                                    <th class="py-3.5 px-4">额外充值频次</th>
                                    <th class="py-3.5 px-4">VIP 状态</th>
                                    <th class="py-3.5 px-4">账号状态</th>
                                    <th class="py-3.5 px-4">首次使用</th>
                                    <th class="py-3.5 px-4 text-right">人工核控操作</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-100">
                                <tr v-for="u in filteredUsers" :key="u.user_id" :class="{'bg-red-50/40': u.is_banned}" class="hover:bg-gray-50/60 transition">
                                    <td class="py-3.5 px-4 font-mono font-bold text-gray-800">
                                        {{ u.user_id }}
                                    </td>
                                    <td class="py-3.5 px-4 text-gray-600">{{ u.daily_quota }} 次</td>
                                    <td class="py-3.5 px-4 text-emerald-600 font-bold">+{{ u.bonus_quota }} 次</td>
                                    <td class="py-3.5 px-4">
                                        <span v-if="u.is_vip" class="px-2.5 py-1 text-[11px] bg-amber-50 text-amber-700 rounded-md font-bold">👑 VIP ({{ u.vip_expire_at ? u.vip_expire_at.split(' ')[0] : '永久' }})</span>
                                        <span v-else class="text-gray-400">普通用户</span>
                                    </td>
                                    <td class="py-3.5 px-4">
                                        <span v-if="u.is_banned" class="px-2 py-0.5 text-[11px] bg-red-100 text-red-700 rounded-md font-bold">🚫 已封禁</span>
                                        <span v-else class="px-2 py-0.5 text-[11px] bg-emerald-100 text-emerald-700 rounded-md font-semibold">正常</span>
                                    </td>
                                    <td class="py-3.5 px-4 text-gray-400">{{ u.created_at }}</td>
                                    <td class="py-3.5 px-4 text-right space-x-1.5 whitespace-nowrap">
                                        <button @click="adjustUser(u.user_id, 'add_quota', 50)" class="px-2 py-1 bg-green-50 text-green-700 hover:bg-green-100 rounded font-medium cursor-pointer">+50次</button>
                                        <button @click="adjustUser(u.user_id, 'sub_quota', 50)" class="px-2 py-1 bg-amber-50 text-amber-700 hover:bg-amber-100 rounded font-medium cursor-pointer">-50次</button>
                                        <button @click="customSetQuota(u)" class="px-2 py-1 bg-blue-50 text-blue-700 hover:bg-blue-100 rounded font-medium cursor-pointer">改次数</button>
                                        <button v-if="!u.is_vip" @click="adjustUser(u.user_id, 'set_vip', 9999)" class="px-2 py-1 bg-purple-50 text-purple-700 hover:bg-purple-100 rounded font-medium cursor-pointer">定为永久VIP</button>
                                        <button v-else @click="adjustUser(u.user_id, 'cancel_vip', 0)" class="px-2 py-1 bg-gray-100 text-gray-700 hover:bg-gray-200 rounded font-medium cursor-pointer">取消VIP</button>
                                        <button v-if="!u.is_banned" @click="toggleBan(u.user_id, true)" class="px-2 py-1 bg-red-50 text-red-600 hover:bg-red-100 rounded font-bold cursor-pointer">🚫 禁用此用户</button>
                                        <button v-else @click="toggleBan(u.user_id, false)" class="px-2 py-1 bg-emerald-100 text-emerald-800 hover:bg-emerald-200 rounded font-bold cursor-pointer">🟢 解除禁用</button>
                                    </td>
                                </tr>
                                <tr v-if="filteredUsers.length === 0">
                                    <td colspan="7" class="py-12 text-center text-gray-400">暂无匹配用户记录</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <!-- TAB 3: 操作日志 -->
            <div v-if="currentTab === 'audit'" class="space-y-6">
                <div class="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
                    <div class="p-5 border-b border-gray-100 flex items-center justify-between">
                        <div>
                            <h3 class="text-sm font-bold text-gray-900">用户与后台操作日志</h3>
                            <p class="text-xs text-gray-400 mt-0.5">记录新用户、解析、兑换及管理员调整操作，显示最近 500 条</p>
                        </div>
                        <input type="text" v-model="searchAudit" placeholder="搜索用户 ID、动作或详情..."
                               class="px-3.5 py-1.5 text-xs bg-gray-50 border border-gray-200 rounded-xl w-64 focus:bg-white focus:outline-none">
                    </div>
                    <div class="overflow-x-auto">
                        <table class="w-full text-left text-xs">
                            <thead class="bg-gray-50/70 border-b border-gray-100 text-gray-400 font-semibold">
                                <tr>
                                    <th class="py-3.5 px-4">时间</th><th class="py-3.5 px-4">用户 ID</th>
                                    <th class="py-3.5 px-4">操作</th><th class="py-3.5 px-4">来源</th><th class="py-3.5 px-4">详情</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-100">
                                <tr v-for="item in filteredAuditLogs" :key="item.id" class="hover:bg-gray-50/60 transition">
                                    <td class="py-3.5 px-4 text-gray-400 whitespace-nowrap">{{ item.created_at }}</td>
                                    <td class="py-3.5 px-4 font-mono font-bold text-gray-800">{{ item.target_user_id || '-' }}</td>
                                    <td class="py-3.5 px-4"><span class="px-2 py-1 rounded-md bg-blue-50 text-blue-700 font-semibold">{{ auditActionName(item.action) }}</span></td>
                                    <td class="py-3.5 px-4 text-gray-500">{{ item.actor === 'admin' ? '管理员' : (item.actor === 'user' ? '用户' : '系统') }}</td>
                                    <td class="py-3.5 px-4 text-gray-600 max-w-md break-all">{{ item.detail || '-' }}</td>
                                </tr>
                                <tr v-if="filteredAuditLogs.length === 0"><td colspan="5" class="py-12 text-center text-gray-400">暂无匹配日志</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <!-- TAB 4: 运营概览 -->
            <div v-if="currentTab === 'overview'" class="space-y-6">
                <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
                    <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm">
                        <div class="text-xs text-gray-400 mb-1">总注册用户</div>
                        <div class="text-2xl font-bold text-gray-900">{{ users.length }}</div>
                        <div class="text-[11px] text-emerald-600 mt-2 font-medium">【钞机汇玩】实时沉淀</div>
                    </div>
                    <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm">
                        <div class="text-xs text-gray-400 mb-1">累计生成卡密</div>
                        <div class="text-2xl font-bold text-gray-900">{{ cards.length }}</div>
                        <div class="text-[11px] text-gray-400 mt-2">包含次数卡与VIP卡</div>
                    </div>
                    <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm">
                        <div class="text-xs text-gray-400 mb-1">未核销卡密</div>
                        <div class="text-2xl font-bold text-amber-600">{{ unusedCardsCount }}</div>
                        <div class="text-[11px] text-amber-600 mt-2">可随时发放或销售</div>
                    </div>
                    <div class="bg-white p-5 rounded-2xl border border-gray-100 shadow-sm">
                        <div class="text-xs text-gray-400 mb-1">VIP 会员数</div>
                        <div class="text-2xl font-bold text-rose-600">{{ vipUsersCount }}</div>
                        <div class="text-[11px] text-rose-600 mt-2">无限次高价值会员</div>
                    </div>
                </div>

                <div class="bg-white p-6 rounded-2xl border border-gray-100 shadow-sm">
                    <h3 class="text-sm font-bold text-gray-800 mb-2">全平台解析通道实时状态</h3>
                    <p class="text-xs text-gray-400 mb-4">全部解析通道均在海外独立 VPS 原生调度，0 依赖第三方收费接口。</p>
                    <div class="grid grid-cols-2 md:grid-cols-7 gap-3">
                        <div class="p-3 bg-gray-50 rounded-xl text-center border border-gray-100">
                            <div class="text-xs font-bold text-gray-700">抖音</div>
                            <span class="inline-block mt-1 text-[10px] text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded font-medium">正常运行</span>
                        </div>
                        <div class="p-3 bg-gray-50 rounded-xl text-center border border-gray-100">
                            <div class="text-xs font-bold text-gray-700">快手</div>
                            <span class="inline-block mt-1 text-[10px] text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded font-medium">正常运行</span>
                        </div>
                        <div class="p-3 bg-gray-50 rounded-xl text-center border border-gray-100">
                            <div class="text-xs font-bold text-gray-700">小红书</div>
                            <span class="inline-block mt-1 text-[10px] text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded font-medium">正常运行</span>
                        </div>
                        <div class="p-3 bg-gray-50 rounded-xl text-center border border-gray-100">
                            <div class="text-xs font-bold text-gray-700">B站</div>
                            <span class="inline-block mt-1 text-[10px] text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded font-medium">正常运行</span>
                        </div>
                        <div class="p-3 bg-gray-50 rounded-xl text-center border border-gray-100">
                            <div class="text-xs font-bold text-gray-700">TikTok</div>
                            <span class="inline-block mt-1 text-[10px] text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded font-medium">正常运行</span>
                        </div>
                        <div class="p-3 bg-gray-50 rounded-xl text-center border border-gray-100">
                            <div class="text-xs font-bold text-gray-700">X (Twitter)</div>
                            <span class="inline-block mt-1 text-[10px] text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded font-medium">4K极速通道</span>
                        </div>
                        <div class="p-3 bg-gray-50 rounded-xl text-center border border-gray-100">
                            <div class="text-xs font-bold text-gray-700">YouTube</div>
                            <span class="inline-block mt-1 text-[10px] text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded font-medium">合成直下</span>
                        </div>
                    </div>
                </div>

                <!-- 最近 100 条解析记录 -->
                <div class="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
                    <div class="p-5 border-b border-gray-100">
                        <h3 class="text-sm font-bold text-gray-900">实时解析调用流水 (最新 100 条)</h3>
                    </div>
                    <div class="overflow-x-auto">
                        <table class="w-full text-left text-xs">
                            <thead class="bg-gray-50 border-b border-gray-100 text-gray-400 font-semibold uppercase">
                                <tr>
                                    <th class="py-3 px-4">调用时间</th>
                                    <th class="py-3 px-4">用户 ID</th>
                                    <th class="py-3 px-4">来源平台</th>
                                    <th class="py-3 px-4">作品标题</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-100">
                                <tr v-for="l in logs" :key="l.id" class="hover:bg-gray-50/60">
                                    <td class="py-3 px-4 text-gray-400 whitespace-nowrap">{{ l.created_at }}</td>
                                    <td class="py-3 px-4 font-mono font-medium">{{ l.user_id }}</td>
                                    <td class="py-3 px-4">
                                        <span class="px-2 py-0.5 rounded bg-gray-100 text-gray-700 font-medium">{{ l.platform }}</span>
                                    </td>
                                    <td class="py-3 px-4 text-gray-600 truncate max-w-md">{{ l.title }}</td>
                                </tr>
                                <tr v-if="logs.length === 0">
                                    <td colspan="4" class="py-8 text-center text-gray-400">暂无解析流水</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <!-- TAB 4: 服务监控 -->
            <div v-if="currentTab === 'services'" class="space-y-6">
                <div class="bg-white p-6 rounded-2xl border border-gray-100 shadow-sm space-y-4">
                    <h3 class="text-sm font-bold text-gray-900">核心服务与守护进程</h3>
                    <div class="space-y-3">
                        <div class="flex items-center justify-between p-4 bg-gray-50 rounded-xl">
                            <div>
                                <div class="text-sm font-bold text-gray-800">FastAPI 解析中枢守护 (videoparser.service)</div>
                                <div class="text-xs text-gray-400 mt-0.5">运行端口：127.0.0.1:8000 · 进程管理：Systemd 开机自启与崩溃自愈</div>
                            </div>
                            <span class="px-2.5 py-1 text-xs bg-emerald-100 text-emerald-800 rounded-lg font-bold">● 运行中</span>
                        </div>
                        <div class="flex items-center justify-between p-4 bg-gray-50 rounded-xl">
                            <div>
                                <div class="text-sm font-bold text-gray-800">Nginx 反向代理与 SSL 引擎</div>
                                <div class="text-xs text-gray-400 mt-0.5">服务域名：sy.sd0739.top · HTTPS Let's Encrypt 证书自动续签</div>
                            </div>
                            <span class="px-2.5 py-1 text-xs bg-emerald-100 text-emerald-800 rounded-lg font-bold">● 正常监听 443</span>
                        </div>
                    </div>
                </div>
            </div>

            <!-- TAB 5: 系统设置 -->
            <div v-if="currentTab === 'settings'" class="space-y-6">
                <div class="bg-white p-6 rounded-2xl border border-gray-100 shadow-sm">
                    <h3 class="text-sm font-bold text-gray-900 mb-2">钞机汇玩系统运营参数</h3>
                    <div class="space-y-3 text-xs text-gray-600">
                        <div class="p-3 bg-gray-50 rounded-xl">
                            <span class="font-bold text-gray-800">每日免费解析额度：</span> 默认为 10 次，每天 00:00 依据客户端 ID 自动补满重置。
                        </div>
                        <div class="p-3 bg-gray-50 rounded-xl">
                            <span class="font-bold text-gray-800">后台管理员密码：</span> 当前已设置为 <code class="font-bold text-rose-600 bg-rose-50 px-1.5 py-0.5 rounded">Aa123450.</code>。
                        </div>
                    </div>
                </div>
            </div>
        </main>
    </div>

    <!-- 登录原生兜底 (即使 Vue 还在载入，点击也能直接登录) -->
    <script>
        function doNativeLogin() {
            const pwd = document.getElementById('pwd-input').value;
            if (!pwd) return;
            fetch('/api/admin/login', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ password: pwd })
            }).then(r => r.json()).then(res => {
                if (res.code === 0) {
                    localStorage.setItem('adm_token', res.token);
                    location.reload();
                } else {
                    alert('密码错误: ' + (res.message || '请重试'));
                }
            }).catch(e => alert('连接失败: ' + e));
        }
    </script>

    <!-- Vue 3 应用主逻辑 -->
    <script>
        const { createApp } = Vue;
        createApp({
            data() {
                return {
                    token: localStorage.getItem('adm_token') || '',
                    loginPwd: '',
                    loggingIn: false,
                    loginErr: '',
                    currentTab: 'cards',
                    users: [],
                    cards: [],
                    logs: [],
                    auditLogs: [],
                    searchCard: '',
                    searchUser: '',
                    searchAudit: '',
                    genType: 'quota_50',
                    genCount: 5,
                    newGeneratedKeys: [],
                    lastUpdatedTime: '-'
                }
            },
            computed: {
                tabName() {
                    return {cards: '卡密与授权', users: '用户与会员', audit: '操作日志', overview: '运营概览', services: '服务监控', settings: '系统设置'}[this.currentTab] || '管理后台';
                },
                tabTitle() {
                    return {cards: '卡密与授权管理', users: '用户与会员中心', audit: '用户与后台操作日志', overview: '数据与运营概览', services: '服务节点与接口监控', settings: '系统参数与通道设置'}[this.currentTab] || '管理后台';
                },
                unusedCardsCount() {
                    return this.cards.filter(c => c.is_used === 0).length;
                },
                vipUsersCount() {
                    return this.users.filter(u => u.is_vip === 1).length;
                },
                filteredCards() {
                    if (!this.searchCard.trim()) return this.cards;
                    const q = this.searchCard.toLowerCase();
                    return this.cards.filter(c => c.card_key.toLowerCase().includes(q) || (c.used_by && c.used_by.toLowerCase().includes(q)));
                },
                filteredUsers() {
                    if (!this.searchUser.trim()) return this.users;
                    const q = this.searchUser.toLowerCase();
                    return this.users.filter(u => u.user_id.toLowerCase().includes(q));
                },
                filteredAuditLogs() {
                    if (!this.searchAudit.trim()) return this.auditLogs;
                    const q = this.searchAudit.toLowerCase();
                    return this.auditLogs.filter(item => [item.target_user_id, item.action, item.actor, item.detail]
                        .some(value => String(value || '').toLowerCase().includes(q)));
                }
            },
            mounted() {
                if (this.token) {
                    this.loadData();
                }
            },
            methods: {
                auditActionName(action) {
                    return {
                        new_user: '新用户进入', parse_success: '解析成功', parse_failed: '解析失败',
                        redeem_card: '兑换卡密', add_quota: '增加次数', sub_quota: '减少次数',
                        set_quota: '设置次数', set_vip: '开通VIP', cancel_vip: '取消VIP',
                        ban_user: '禁用用户', unban_user: '解除禁用', reset: '重置用户'
                    }[action] || action;
                },
                async handleLogin() {
                    if (!this.loginPwd) return;
                    this.loggingIn = true;
                    this.loginErr = '';
                    try {
                        const res = await fetch('/api/admin/login', {
                            method: 'POST',
                            headers: {'Content-Type': 'application/json'},
                            body: JSON.stringify({ password: this.loginPwd })
                        }).then(r => r.json());
                        if (res.code === 0) {
                            this.token = res.token;
                            localStorage.setItem('adm_token', res.token);
                            this.loadData();
                        } else {
                            this.loginErr = res.message || '密码错误';
                        }
                    } catch (e) {
                        this.loginErr = '连接服务器失败';
                    } finally {
                        this.loggingIn = false;
                    }
                },
                logout() {
                    this.token = '';
                    localStorage.removeItem('adm_token');
                },
                async loadData() {
                    if (!this.token) return;
                    try {
                        const res = await fetch('/api/admin/data?token=' + this.token).then(r => r.json());
                        if (res.code === 0) {
                            this.users = res.users;
                            this.cards = res.cards;
                            this.logs = res.logs;
                            this.auditLogs = res.audit_logs || [];
                            const d = new Date();
                            this.lastUpdatedTime = `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}`;
                        }
                    } catch (e) {
                        console.error('加载后台数据失败', e);
                    }
                },
                async handleGenerateCards() {
                    let card_type = 'quota';
                    let card_val = 50;
                    if (this.genType === 'quota_100') card_val = 100;
                    if (this.genType === 'quota_500') card_val = 500;
                    if (this.genType === 'vip_30') { card_type = 'vip'; card_val = 30; }
                    if (this.genType === 'vip_permanent') { card_type = 'vip'; card_val = 9999; }

                    const res = await fetch('/api/admin/generate_cards', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({ card_type, card_val, count: this.genCount })
                    }).then(r => r.json());
                    if (res.code === 0) {
                        this.newGeneratedKeys = res.keys;
                        this.loadData();
                    }
                },
                async adjustUser(user_id, action, value) {
                    const res = await fetch('/api/admin/adjust_user', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({ user_id, action, value })
                    }).then(r => r.json());
                    if (res.code === 0) {
                        this.loadData();
                    }
                },
                async customSetQuota(u) {
                    const tip = '请输入要为用户 [' + u.user_id + '] 设置的额外赠送解析次数：' + String.fromCharCode(10) + '（当前为 +' + u.bonus_quota + ' 次）';
                    const input = prompt(tip, u.bonus_quota);
                    if (input !== null && input.trim() !== '' && !isNaN(parseInt(input))) {
                        await this.adjustUser(u.user_id, 'set_quota', parseInt(input.trim()));
                    }
                },
                async toggleBan(user_id, toBan) {
                    const tip = toBan 
                        ? ('确定要禁用用户 [' + user_id + '] 吗？' + String.fromCharCode(10) + '禁用后该用户将立即无法进行视频解析和卡密兑换！')
                        : ('确定要为用户 [' + user_id + '] 解除禁用恢复正常使用吗？');
                    if (confirm(tip)) {
                        await this.adjustUser(user_id, toBan ? 'ban_user' : 'unban_user', 0);
                    }
                },
                copyText(txt) {
                    navigator.clipboard.writeText(txt);
                    alert('已复制卡密：' + txt);
                },
                copyAllKeys() {
                    navigator.clipboard.writeText(this.newGeneratedKeys.join(String.fromCharCode(10)));
                    alert('已成功复制全部 ' + this.newGeneratedKeys.length + ' 张卡密！');
                }
            }
        }).mount('#app');
    </script>
</body>
</html>
"""

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
