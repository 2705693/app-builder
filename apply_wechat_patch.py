# -*- coding: utf-8 -*-
from pathlib import Path

p = Path("server/main.py")
s = p.read_text(encoding="utf-8")

if "def parse_wechat_channels(" in s:
    print("检测到视频号接入代码已经存在，未重复修改")
else:
    import_anchor = "import requests\n"
    if import_anchor not in s:
        import_anchor = "import requests\r\n"
    if import_anchor not in s:
        raise SystemExit("找不到 import requests，未修改")
    s = s.replace(
        import_anchor,
        import_anchor + "from urllib.parse import urlparse\n",
        1
    )

    parse_code = r'''
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

'''

    class_anchor = "class ParseRequest(BaseModel):"
    if class_anchor not in s:
        raise SystemExit("找不到 ParseRequest，未修改")
    s = s.replace(class_anchor, parse_code + class_anchor, 1)

    branch_anchor = '        elif "twitter.com" in target_url or "x.com" in target_url:\n'
    if branch_anchor not in s:
        branch_anchor = '        elif "twitter.com" in target_url or "x.com" in target_url:\r\n'
    branch_code = '''        elif "weixin.qq.com" in target_url or "channels.weixin.qq.com" in target_url:
            result = parse_wechat_channels(target_url)
            platform = "视频号"
'''
    if branch_anchor not in s:
        raise SystemExit("找不到平台判断位置，未修改")
    s = s.replace(branch_anchor, branch_code + branch_anchor, 1)

    proxy_code = r'''
@app.get("/api/wechat_proxy")
def wechat_proxy_stream(
    request: Request,
    url: str = Query(..., description="视频号媒体地址"),
    key: str = Query("", description="视频号媒体解密参数"),
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

    response_headers = {
        "Content-Disposition": "inline; filename=wechat-video.mp4",
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

'''

    admin_anchor = '@app.post("/api/admin/login")'
    if admin_anchor not in s:
        raise SystemExit("找不到管理员接口位置，未修改")
    s = s.replace(admin_anchor, proxy_code + admin_anchor, 1)

    p.write_text(s, encoding="utf-8")
    print("视频号接入代码已成功同步写入 server/main.py")
