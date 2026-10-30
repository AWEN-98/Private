from app import extract_items, playable_url, is_https_video

def test_h264_preferred():
    data={"play_addr":{"url_list":["https://cdn.example.com/default.mp4"]},"bit_rate":[{"codec_type":"h265","play_addr":{"url_list":["https://cdn.example.com/hevc.mp4"]}},{"codec_type":"h264","play_addr":{"url_list":["https://cdn.example.com/avc.mp4"]}}]}
    assert playable_url(data).endswith("avc.mp4")

def test_nested_feed_and_deduplication():
    item={"aweme_id":"123","desc":"First","video":{"play_addr":{"url_list":["https://cdn.example.com/1.mp4"]}}}
    result=extract_items({"data":{"aweme_list":[item,item,{"aweme_id":"456","video":{"play_addr":{"url_list":["https://cdn.example.com/2.mp4"]}}}]}})
    assert len(result)==2
    assert result[0]["title"]=="First"
    assert result[1]["id"]=="456"

def test_reject_non_https():
    assert not is_https_video("http://cdn.example.com/video.mp4")
    assert not is_https_video("file:///etc/passwd")
    assert extract_items({"video":{"play_addr":{"url_list":["http://bad.example/video"]}}}) == []

def test_empty_and_challenge_responses():
    assert extract_items({"status_code":0,"aweme_list":[]})==[]
    assert extract_items({"page_title":"验证码中间页"})==[]

def test_login_cookie_status_never_returns_cookie_value():
    import asyncio
    from app import BrowserFeed
    class FakeContext:
        async def cookies(self, url):
            return [{"name": "sessionid_ss", "value": "private-session-should-not-leak"}]
    engine = BrowserFeed()
    engine.context = FakeContext()
    status = asyncio.run(engine.session_info())
    assert status["session_cookie_present"] is True
    assert status["login_verified"] is False
    assert "private-session-should-not-leak" not in str(status)

def test_guest_session_is_not_falsely_marked_logged_in():
    import asyncio
    from app import BrowserFeed
    class FakeContext:
        async def cookies(self, url):
            return [{"name": "msToken", "value": "public-guest-marker"}]
    engine = BrowserFeed()
    engine.context = FakeContext()
    status = asyncio.run(engine.session_info())
    assert status["session_cookie_present"] is False

def test_remote_browser_frame_and_tap_are_authorized(monkeypatch):
    import asyncio
    import app as bridge
    from fastapi import HTTPException
    class FakeRequest:
        headers={"authorization":"Bearer a-valid-test-secret"}
    class FakePage:
        def __init__(self):
            self.taps=[]
        async def screenshot(self, **kwargs):
            assert kwargs["type"]=="jpeg"
            return b"fake-jpeg-bytes"
        class Mouse:
            def __init__(self, parent): self.parent=parent
            async def click(self, x, y, **kwargs): self.parent.taps.append((x,y))
        @property
        def mouse(self): return self.Mouse(self)
    page=FakePage()
    monkeypatch.setattr(bridge,"KEY","a-valid-test-secret")
    monkeypatch.setattr(bridge.engine,"page",page)
    frame=asyncio.run(bridge.browser_frame(FakeRequest()))
    assert frame.body==b"fake-jpeg-bytes"
    assert frame.headers["cache-control"].startswith("private")
    assert frame.headers["x-viewport-width"]=="1280"
    result=asyncio.run(bridge.browser_tap(FakeRequest(),bridge.BrowserTap(x=120,y=180)))
    assert result["ok"] and page.taps==[(120.0,180.0)]
    class BadRequest:
        headers={"authorization":"Bearer invalid"}
    try:
        asyncio.run(bridge.browser_frame(BadRequest()))
        assert False, "Remote browser leaked screen without the bridge key"
    except HTTPException as exc:
        assert exc.status_code==401

def test_remote_browser_coordinates_clamped():
    import pytest
    from pydantic import ValidationError
    from app import BrowserTap, BrowserScroll
    with pytest.raises(ValidationError):
        BrowserTap(x=-1,y=200)
    with pytest.raises(ValidationError):
        BrowserTap(x=1281,y=200)
    with pytest.raises(ValidationError):
        BrowserScroll(dy=99999)


def test_hls_segment_safety_and_ticket():
    from streamer import valid_segment, playlist_with_ticket
    assert valid_segment("chunk000042.ts")
    assert not valid_segment("../secret.txt")
    assert not valid_segment("chunk000042.ts/../secret")
    assert not valid_segment("evil.ts")
    manifest = "#EXTM3U\n#EXTINF:2.0,\nchunk000001.ts\n#EXTINF:2.0,\nchunk000002.ts\n"
    translated = playlist_with_ticket(manifest, "testtoken")
    assert "chunk000001.ts?ticket=testtoken" in translated
    assert "chunk000002.ts?ticket=testtoken" in translated


def test_encoder_audio_is_explicit_and_baseline():
    from streamer import encoder_args
    with_audio = encoder_args("index.m3u8", "chunk%06d.ts", "douyin_capture.monitor")
    assert with_audio[with_audio.index("-profile:v") + 1] == "baseline"
    assert with_audio[with_audio.index("-c:a") + 1] == "aac"
    assert "douyin_capture.monitor" in with_audio
    without_audio = encoder_args("index.m3u8", "chunk%06d.ts")
    assert "-an" in without_audio and "-c:a" not in without_audio

def test_audio_only_selects_named_virtual_sink(monkeypatch):
    from streamer import available_audio_source
    class Result:
        stdout = "1\tdouyin_capture.monitor\tmodule-null-sink\n"
    monkeypatch.setenv("DOUYIN_AUDIO_SOURCE", "douyin_capture.monitor")
    monkeypatch.setenv("DOUYIN_AUDIO_ENABLED", "1")
    monkeypatch.setattr("streamer.shutil.which", lambda _: "/usr/bin/pactl")
    monkeypatch.setattr("streamer.subprocess.run", lambda *args, **kwargs: Result())
    assert available_audio_source() == "douyin_capture.monitor"
    monkeypatch.setenv("DOUYIN_AUDIO_SOURCE", "not-installed.monitor")
    assert available_audio_source() is None



def test_public_share_page_with_nested_router_data():
    import json
    from share import parse_public_html
    payload = {"loaderData": {"video_(123)/page": {"videoInfoRes": {
        "item_list": [{"aweme_id": "7234567890123456789",
                       "desc": "This is a public clip",
                       "video": {"play_addr": {"url_list": ["https://media.example/video.mp4?a=1&b=2"]},
                                 "bit_rate": [{"codec_type": "h265",
                                               "play_addr": {"url_list": ["https://media.example/h265.mp4"]}},
                                              {"codec_type": "h264",
                                               "bit_rate": 330000,
                                               "play_addr": {"url_list": ["https://media.example/avc.mp4"]}}]}}]
    }}}}
    html = "<script>window._ROUTER_DATA = " + json.dumps(payload) + ";</script>"
    clip = parse_public_html(html)
    assert clip["url"] == "https://media.example/avc.mp4"
    assert clip["title"] == "This is a public clip"


def test_official_share_id_validation():
    from share import official_link, video_id, mobile_share_url
    assert video_id("https://www.douyin.com/video/7234567890123456789") == "7234567890123456789"
    assert video_id("https://www.douyin.com/?modal_id=7234567890123456789") == "7234567890123456789"
    assert mobile_share_url("7234567890123456789") == "https://www.iesdouyin.com/share/video/7234567890123456789/"
    for dangerous in ("http://www.douyin.com/video/7234567890123456789",
                      "https://douyin.com.attacker.test/video/7234567890123456789",
                      "https://127.0.0.1/video/7234567890123456789",
                      "https://www.douyin.com:8443/video/7234567890123456789"):
        assert not official_link(dangerous)


def test_public_share_resolution_falls_back_to_mobile_page(monkeypatch):
    import asyncio
    import json
    import app as bridge

    share = "https://www.douyin.com/video/7234567890123456789"
    public = "https://www.iesdouyin.com/share/video/7234567890123456789/"
    nested = {"loaderData": {"video_x/page": {"videoInfoRes": {"item_list": [
        {"desc": "Public", "video": {"play_addr": {"url_list": ["https://media.example/actual.mp4"]}}}
    ]}}}}
    class FakeResponse:
        def __init__(self, url, body):
            self.url = url
            self.status = 200
            self._body = body
        async def body(self):
            return self._body
    class FakeAPI:
        def __init__(self):
            self.visited = []
        async def get(self, url, **kwargs):
            self.visited.append(url)
            if url == public:
                return FakeResponse(url, ("window._ROUTER_DATA=" + json.dumps(nested)).encode())
            return FakeResponse(url, b"<html>Web JS shell only</html>")
    class FakeBrowserContext:
        request = FakeAPI()
    class FakeRequest:
        headers = {"authorization": "Bearer valid-test-bridge-secret"}
    fake = FakeBrowserContext()
    monkeypatch.setattr(bridge, "KEY", "valid-test-bridge-secret")
    monkeypatch.setattr(bridge.engine, "context", fake)
    result = asyncio.run(bridge.resolve_public_share(
        FakeRequest(), bridge.PublicShareRequest(url=share)))
    assert result["url"] == "https://media.example/actual.mp4"
    assert fake.request.visited == [share, public]
