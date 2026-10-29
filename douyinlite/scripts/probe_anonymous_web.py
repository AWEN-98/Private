import asyncio,json,time
from pathlib import Path
from urllib.parse import urlparse
from playwright.async_api import async_playwright

report={"utc":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),"responses":[],"errors":[],"videos":[]}
items=[]; seen=set()
def scan(x,depth=0):
    if depth>12:return
    if isinstance(x,list):
        for v in x[:100]:scan(v,depth+1)
    elif isinstance(x,dict):
        video=x.get("video")
        if isinstance(video,dict):
            links=[]
            rates=video.get("bit_rate")
            if isinstance(rates,list):
                for rate in rates:
                    if not isinstance(rate,dict):continue
                    codec=str(rate.get("codec_type","")).lower()
                    if codec and "264" not in codec and codec!="avc":continue
                    addr=rate.get("play_addr",{})
                    if isinstance(addr,dict) and isinstance(addr.get("url_list"),list):links+=addr["url_list"]
            addr=video.get("play_addr",{})
            if isinstance(addr,dict) and isinstance(addr.get("url_list"),list):links+=addr["url_list"]
            link=next((u for u in links if isinstance(u,str) and u.startswith("https://")),None)
            vid=str(x.get("aweme_id") or x.get("id") or "")
            if link and vid not in seen and len(items)<30:
                seen.add(vid);items.append({"url":link,"title":str(x.get("desc") or "公开视频")[:100],"id":vid,"source":"douyin-public-web"})
        for v in x.values():
            if isinstance(v,(dict,list)):scan(v,depth+1)

async def main():
    tasks=[]
    async with async_playwright() as pw:
        browser=await pw.chromium.launch(channel="chrome",headless=True,args=["--no-sandbox"])
        page=await browser.new_page(viewport={"width":1280,"height":800})
        async def on_response(r):
            if "douyin.com" not in r.url:return
            if len(report["responses"])<50 and ("/aweme/" in r.url or "/webcast/" in r.url or r.url.rstrip("/").endswith("douyin.com")):
                report["responses"].append({"status":r.status,"path":urlparse(r.url).path})
            if "/aweme/" not in r.url or "json" not in r.headers.get("content-type",""):return
            try:scan(await r.json())
            except Exception as e:
                if len(report["errors"])<8:report["errors"].append("response:"+str(e)[:140])
        page.on("response",lambda r:tasks.append(asyncio.create_task(on_response(r))))
        page.on("pageerror",lambda e:report["errors"].append("js:"+str(e)[:180]) if len(report["errors"])<8 else None)
        try:
            response=await page.goto("https://www.douyin.com/",wait_until="domcontentloaded",timeout=40000)
            report["status"]=response.status if response else None
            await page.wait_for_timeout(12000)
            await page.mouse.wheel(0,700)
            await page.wait_for_timeout(5000)
            report["page_title"]=(await page.title())[:110]
            report["video_count"]=await page.locator("video").count()
        except Exception as e:report["errors"].append("navigation:"+str(e)[:180])
        if tasks:await asyncio.gather(*tasks,return_exceptions=True)
        await browser.close()
    report["items"]=len(items)
    Path("diagnostics").mkdir(exist_ok=True)
    Path("diagnostics/douyin-anonymous-probe.json").write_text(json.dumps(report,ensure_ascii=False,indent=2))
    if items:
        Path("downloads").mkdir(exist_ok=True)
        Path("downloads/douyin-public-feed.json").write_text(json.dumps({"data":items,"next":None},ensure_ascii=False,indent=2))
    print(json.dumps(report,ensure_ascii=False))
asyncio.run(main())
