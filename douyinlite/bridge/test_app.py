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
