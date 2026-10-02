#!/usr/bin/env python3
"""Render and audit standalone Android design mockups, without network access.

Run from any directory with the already installed Python Playwright and Pillow:
    python3 docs/design/v2/render_mockups.py

Chromium is intentionally taken from /usr/bin/chromium rather than downloaded.
The script reads screens.json; it never invokes or modifies build_mockups.py.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont
from playwright.sync_api import sync_playwright


PHONE_WIDTH = 390
PHONE_HEIGHT = 844
DEVICE_SCALE = 2
MIN_TARGET = 48
ROOT = Path(__file__).resolve().parent
FONT_DIRECTORY = Path("/usr/share/fonts/truetype/dejavu")


MEASURE_SCRIPT = r"""() => {
    const phone = document.querySelector('.phone');
    if (!phone) throw new Error('Missing .phone element');
    const rect = e => {
        const r = e.getBoundingClientRect();
        return {x:r.x, y:r.y, width:r.width, height:r.height};
    };
    const identify = e => {
        const classes = [...e.classList].slice(0, 3).join('.');
        return e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') +
            (classes ? '.' + classes : '');
    };
    const label = e => (e.getAttribute('aria-label') || e.getAttribute('title') ||
        e.getAttribute('placeholder') || e.innerText || e.value || '')
        .replace(/\s+/g, ' ').trim().slice(0, 120);
    const selector = 'button,a[href],input:not([type=hidden]),textarea,select,' +
        'summary,[role=button],[role=switch],[onclick],[data-go],[data-demo]';
    const rendered = e => {
        const r = e.getBoundingClientRect();
        const s = getComputedStyle(e);
        return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' &&
            s.display !== 'none' && !e.disabled && !e.closest('[inert]');
    };
    const targets = [...phone.querySelectorAll(selector)].filter(rendered)
        .map((e, index) => ({index, element:identify(e), label:label(e), ...rect(e),
            pass:e.getBoundingClientRect().width >= 48 - .01 &&
                e.getBoundingClientRect().height >= 48 - .01}));
    const roots = [document.documentElement, document.body, phone,
        ...phone.querySelectorAll('.scroll')];
    const horizontal = roots.map(e => ({element:identify(e),
        clientWidth:e.clientWidth, scrollWidth:e.scrollWidth,
        overflow:getComputedStyle(e).overflowX,
        pass:e.scrollWidth <= e.clientWidth + 1}));
    const overflowDetails = [];
    for (const scroll of phone.querySelectorAll('.scroll')) {
        if (scroll.scrollWidth <= scroll.clientWidth + 1) continue;
        const sr = scroll.getBoundingClientRect();
        for (const e of scroll.querySelectorAll('*')) {
            const r = e.getBoundingClientRect();
            if (!r.width || (r.left >= sr.left - 1 && r.right <= sr.right + 1))
                continue;
            let clipped = false;
            for (let ancestor=e.parentElement; ancestor && ancestor !== scroll;
                    ancestor=ancestor.parentElement) {
                if (['hidden','clip'].includes(getComputedStyle(ancestor).overflowX)) {
                    clipped = true;
                    break;
                }
            }
            if (!clipped) overflowDetails.push({element:identify(e),
                label:label(e), ...rect(e)});
        }
    }
    const faces = [...document.fonts].map(f => ({family:f.family,
        status:f.status, style:f.style, weight:f.weight}));
    const fontChecks = [400, 700, 800].map(weight => ({weight,
        loaded:document.fonts.check(weight + ' 16px Manrope',
            'Мору — мысль и дело 0123456789')}));
    return {
        phone:rect(phone),
        document:{width:document.documentElement.clientWidth,
            height:document.documentElement.clientHeight,
            scrollWidth:document.documentElement.scrollWidth,
            scrollHeight:document.documentElement.scrollHeight},
        horizontal:{pass:horizontal.every(r => r.pass), roots:horizontal,
            overflowDetails},
        targets:{minimum:{width:48,height:48}, count:targets.length,
            pass:targets.every(t => t.pass),
            failures:targets.filter(t => !t.pass), all:targets},
        fonts:{status:document.fonts.status,
            bodyFamily:getComputedStyle(document.body).fontFamily,
            declaredFaces:faces, checks:fontChecks,
            pass:document.fonts.status === 'loaded' &&
                faces.some(f => f.family.replace(/["']/g,'') === 'Manrope' &&
                    f.status === 'loaded') && fontChecks.every(f => f.loaded)}
    };
}"""


SCROLL_SCRIPT = r"""async () => {
    const phone = document.querySelector('.phone');
    const selector = 'button,a[href],input:not([type=hidden]),textarea,select,' +
        'summary,[role=button],[role=switch],[onclick],[data-go],[data-demo]';
    const frame = () => new Promise(resolve => requestAnimationFrame(resolve));
    const label = e => (e.getAttribute('aria-label') || e.getAttribute('title') ||
        e.getAttribute('placeholder') || e.innerText || e.value || '')
        .replace(/\s+/g, ' ').trim().slice(0,120);
    const identify = e => e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') +
        (e.classList.length ? '.' + [...e.classList].slice(0,3).join('.') : '');
    const visibleRect = e => {
        const r = e.getBoundingClientRect();
        let left=r.left, right=r.right, top=r.top, bottom=r.bottom;
        for (let a=e.parentElement; a; a=a.parentElement) {
            const s=getComputedStyle(a), ar=a.getBoundingClientRect();
            if (s.overflowX !== 'visible') {
                left=Math.max(left,ar.left); right=Math.min(right,ar.right);
            }
            if (s.overflowY !== 'visible') {
                top=Math.max(top,ar.top); bottom=Math.min(bottom,ar.bottom);
            }
        }
        left=Math.max(0,left); right=Math.min(innerWidth,right);
        top=Math.max(0,top); bottom=Math.min(innerHeight,bottom);
        return {left,right,top,bottom,width:Math.max(0,right-left),
            height:Math.max(0,bottom-top)};
    };
    const results=[];
    for (const [index, scroll] of [...phone.querySelectorAll('.scroll')].entries()) {
        scroll.scrollTop=0;
        await frame();
        const initial=scroll.getBoundingClientRect();
        const maxScrollTop=Math.max(0,scroll.scrollHeight-scroll.clientHeight);
        const deeper=[...scroll.querySelectorAll(selector)].filter(e => {
            const r=e.getBoundingClientRect(), s=getComputedStyle(e);
            return r.width > 0 && r.height > 0 && !e.disabled &&
                !e.closest('[inert]') && s.visibility !== 'hidden' &&
                r.bottom > initial.bottom + 1;
        });
        scroll.scrollTop=maxScrollTop;
        await frame();
        const reachedBottom=Math.abs(scroll.scrollTop-maxScrollTop) <= 1;
        const moved=maxScrollTop <= 1 || scroll.scrollTop > 0;
        const controls=[];
        for (const e of deeper) {
            e.scrollIntoView({block:'center',inline:'nearest',behavior:'instant'});
            await frame();
            const r=visibleRect(e);
            const hit=r.width > 0 && r.height > 0 ? document.elementFromPoint(
                (r.left+r.right)/2,(r.top+r.bottom)/2) : null;
            const reachable=!!hit && (hit === e || e.contains(hit));
            controls.push({element:identify(e), label:label(e),
                scrollTop:scroll.scrollTop, visibleWidth:r.width,
                visibleHeight:r.height, reachable,
                obstruction:reachable ? null : hit ? identify(hit) : null});
        }
        results.push({index, clientHeight:scroll.clientHeight,
            scrollHeight:scroll.scrollHeight, maxScrollTop,
            requiresScrolling:maxScrollTop > 1, moved, reachedBottom,
            deeperControls:controls,
            pass:moved && reachedBottom && controls.every(e => e.reachable)});
        scroll.scrollTop=0;
        scroll.scrollLeft=0;
    }
    window.scrollTo(0,0);
    await frame();
    await frame();
    return {verticalOverflowAllowed:true,
        pass:results.every(r => r.pass), containers:results};
}"""


def relative_file(root: Path, filename: str) -> Path:
    """Keep generated artifacts inside the explicitly selected design folder."""
    path = (root / filename).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f"Manifest path is outside the design folder: {filename}")
    return path


def platform_fonts(page) -> list[dict]:
    """Record Chromium's actual fonts, rather than just the CSS family list."""
    session = page.context.new_cdp_session(page)
    try:
        session.send("DOM.enable")
        session.send("CSS.enable")
        document = session.send("DOM.getDocument")
        nodes = session.send("DOM.querySelectorAll", {
            "nodeId": document["root"]["nodeId"],
            "selector": "h1,h2,h3,p,b,small,.system-time,.user-message",
        })["nodeIds"]
        fonts = {}
        for node_id in nodes[:8]:
            for font in session.send("CSS.getPlatformFontsForNode", {
                "nodeId": node_id,
            })["fonts"]:
                key = (font["familyName"], font["isCustomFont"])
                entry = fonts.setdefault(key, {
                    "family": font["familyName"],
                    "custom": font["isCustomFont"],
                    "sampledGlyphCount": 0,
                })
                entry["sampledGlyphCount"] += font["glyphCount"]
        return sorted(fonts.values(), key=lambda font: font["family"])
    finally:
        session.detach()


def render_screen(browser, root: Path, screen: dict, timeout: int) -> dict:
    result = {key: screen[key] for key in ("id", "key", "title", "theme", "html", "png")}
    result.update({"browserErrors": [], "consoleWarnings": [],
        "blockedRequests": [], "failedRequests": []})
    context = browser.new_context(
        viewport={"width": PHONE_WIDTH, "height": PHONE_HEIGHT},
        device_scale_factor=DEVICE_SCALE,
        locale="ru-RU",
        timezone_id="UTC",
        color_scheme=screen["theme"],
        reduced_motion="reduce",
        service_workers="block",
    )
    page = context.new_page()
    page.set_default_timeout(timeout)
    html_path = relative_file(root, screen["html"])
    def route_request(route):
        request = route.request
        result["blockedRequests"].append({
            "url": request.url,
            "type": request.resource_type,
        })
        route.abort("blockedbyclient")

    def console_message(message):
        if message.type == "error":
            result["browserErrors"].append({"type": "console", "message": message.text})
        elif message.type == "warning":
            result["consoleWarnings"].append(message.text)

    page.route("**/*", route_request)
    page.on("console", console_message)
    page.on("pageerror", lambda error: result["browserErrors"].append({
        "type": "javascript", "message": str(error),
    }))
    page.on("requestfailed", lambda request: result["failedRequests"].append({
        "url": request.url, "type": request.resource_type, "failure": request.failure,
    }))
    try:
        # Load the exact HTML bytes into an inert about:blank document. Some
        # managed Chromium installations prohibit file:// navigation. Embedded
        # fonts/SVG need no URL base; every attempted request remains blocked.
        page.set_content(html_path.read_text(encoding="utf-8"), wait_until="load")
        page.evaluate("async () => { await document.fonts.ready; "
            "await new Promise(r => requestAnimationFrame(r)); "
            "await new Promise(r => requestAnimationFrame(r)); }")
        measurements = page.evaluate(MEASURE_SCRIPT)
        result.update(measurements)
        fonts = platform_fonts(page)
        result["fonts"]["platformFonts"] = fonts
        result["fonts"]["pass"] = result["fonts"]["pass"] and any(
            # The embedded variable TTF reports its native family as
            # "Manrope ExtraLight", while @font-face names it "Manrope".
            (font["family"] == "Manrope" or font["family"].startswith("Manrope "))
            and font["custom"]
            and font["sampledGlyphCount"] > 0 for font in fonts
        )
        result["scroll"] = page.evaluate(SCROLL_SCRIPT)
        phone = page.locator(".phone").bounding_box()
        result["phoneDimensionsPass"] = (
            abs(phone["width"] - PHONE_WIDTH) < .01
            and abs(phone["height"] - PHONE_HEIGHT) < .01
            and abs(phone["x"]) < .01 and abs(phone["y"]) < .01
        )
        png_path = relative_file(root, screen["png"])
        png_path.parent.mkdir(parents=True, exist_ok=True)
        # An explicit fixed clip captures the phone only, including at DPR 2.
        page.screenshot(
            path=str(png_path),
            clip={"x": phone["x"], "y": phone["y"],
                "width": PHONE_WIDTH, "height": PHONE_HEIGHT},
            animations="disabled", caret="hide", scale="device",
        )
        with Image.open(png_path) as image:
            size = list(image.size)
        result["screenshot"] = {
            "width": size[0], "height": size[1],
            "pass": size == [PHONE_WIDTH * DEVICE_SCALE, PHONE_HEIGHT * DEVICE_SCALE],
            "sha256": hashlib.sha256(png_path.read_bytes()).hexdigest(),
        }
        result["selfContainedPass"] = not result["blockedRequests"]
        result["browserErrorsPass"] = not result["browserErrors"] and not result["failedRequests"]
        result["pass"] = all((
            result["phoneDimensionsPass"], result["screenshot"]["pass"],
            result["horizontal"]["pass"], result["targets"]["pass"],
            result["fonts"]["pass"], result["scroll"]["pass"],
            result["selfContainedPass"], result["browserErrorsPass"],
        ))
    except Exception as error:
        result["renderException"] = f"{type(error).__name__}: {error}"
        result["pass"] = False
    finally:
        context.close()
    return result


def wrap_text(draw, text: str, font, width: int) -> list[str]:
    lines = []
    current = ""
    for word in text.split():
        candidate = f"{current} {word}".strip()
        if current and draw.textlength(candidate, font=font) > width:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines


def make_board(root: Path, screens: list[dict], results: list[dict]) -> dict:
    groups = {}
    for screen in screens:
        groups.setdefault(screen["key"], {})[screen["theme"]] = screen
    pairs = list(groups.values())
    fonts = {
        "title": ImageFont.truetype(str(FONT_DIRECTORY / "DejaVuSans-Bold.ttf"), 36),
        "label": ImageFont.truetype(str(FONT_DIRECTORY / "DejaVuSans-Bold.ttf"), 23),
        "small": ImageFont.truetype(str(FONT_DIRECTORY / "DejaVuSans.ttf"), 18),
    }
    margin, gap, pair_gap = 28, 16, 32
    pair_width = PHONE_WIDTH * 2 + gap
    width = margin * 2 + pair_width * 2 + pair_gap
    header_height, row_header, row_gap = 126, 96, 34
    row_height = row_header + PHONE_HEIGHT + row_gap
    height = header_height + math.ceil(len(pairs) / 2) * row_height + margin
    board = Image.new("RGB", (width, height), "#ECEDEB")
    draw = ImageDraw.Draw(board)
    draw.text((margin, 24), "Moru v2 · все экраны", font=fonts["title"], fill="#20222B")
    draw.text((margin, 76),
        f"Android · {len(pairs)} сценариев · светлая и тёмная темы · "
        "каждый экран 390 × 844 · исходные PNG @2x",
        font=fonts["small"], fill="#626570")
    successful = {result["png"] for result in results if "screenshot" in result}
    missing = []
    for index, pair in enumerate(pairs):
        row, pair_column = divmod(index, 2)
        pair_x = margin + pair_column * (pair_width + pair_gap)
        row_y = header_height + row * row_height
        sample = next(iter(pair.values()))
        title = f"{sample['id']:02d}. {sample['title']}"
        lines = wrap_text(draw, title, fonts["label"], pair_width)
        for line_index, line in enumerate(lines):
            draw.text((pair_x, row_y + line_index * 29), line,
                font=fonts["label"], fill="#20222B")
        for theme_column, (theme, label) in enumerate((
            ("light", "Светлая тема"), ("dark", "Тёмная тема"),
        )):
            x = pair_x + theme_column * (PHONE_WIDTH + gap)
            draw.text((x, row_y + 62), label,
                font=fonts["small"], fill="#626570")
            y = row_y + row_header
            screen = pair.get(theme)
            if not screen or screen["png"] not in successful:
                missing.append({"key": sample["key"], "theme": theme})
                continue
            with Image.open(relative_file(root, screen["png"])) as source:
                thumbnail = source.convert("RGB").resize(
                    (PHONE_WIDTH, PHONE_HEIGHT), Image.Resampling.LANCZOS,
                )
                board.paste(thumbnail, (x, y))
    board_path = root / "board.png"
    board.save(board_path, format="PNG", optimize=True)
    return {"path": "board.png", "width": width, "height": height,
        "columns": 4, "pairsPerRow": 2, "screens": len(successful),
        "screenSize": {"width": PHONE_WIDTH, "height": PHONE_HEIGHT},
        "missingScreens": missing, "pass": not missing,
        "sha256": hashlib.sha256(board_path.read_bytes()).hexdigest()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT,
        help="Design folder containing screens.json (default: this script's folder)")
    parser.add_argument("--chromium", type=Path, default=Path("/usr/bin/chromium"),
        help="Installed Chromium executable; no browser download is performed")
    parser.add_argument("--timeout", type=int, default=15000,
        help="Playwright timeout in milliseconds (default: 15000)")
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        screens = json.loads((root / "screens.json").read_text(encoding="utf-8"))
        if not screens:
            raise ValueError("screens.json is empty")
        seen = set()
        for screen in screens:
            for key in ("id", "key", "title", "theme", "html", "png"):
                if key not in screen:
                    raise ValueError(f"Manifest screen is missing {key}")
            if screen["theme"] not in ("light", "dark"):
                raise ValueError(f"Unknown theme: {screen['theme']}")
            pair = (screen["key"], screen["theme"])
            if pair in seen:
                raise ValueError(f"Duplicate manifest screen: {pair}")
            seen.add(pair)
            if not relative_file(root, screen["html"]).is_file():
                raise FileNotFoundError(screen["html"])
            relative_file(root, screen["png"])
        if not args.chromium.is_file():
            raise FileNotFoundError(args.chromium)
    except (OSError, ValueError, TypeError) as error:
        print(f"Cannot render mockups: {error}", file=sys.stderr)
        return 2

    results = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            executable_path=str(args.chromium), headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage", "--force-color-profile=srgb"],
        )
        browser_version = browser.version
        try:
            for screen in screens:
                result = render_screen(browser, root, screen, args.timeout)
                results.append(result)
                status = "PASS" if result["pass"] else "FAIL"
                print(f"{status} {screen['key']}-{screen['theme']}", flush=True)
        finally:
            browser.close()

    board = make_board(root, screens, results)
    check_paths = {
        "phoneDimensions": ("phoneDimensionsPass",),
        "screenshotDimensions": ("screenshot", "pass"),
        "horizontalOverflow": ("horizontal", "pass"),
        "targetDimensions": ("targets", "pass"),
        "fontLoads": ("fonts", "pass"),
        "verticalScrollReachability": ("scroll", "pass"),
        "selfContained": ("selfContainedPass",),
        "browserErrors": ("browserErrorsPass",),
    }
    checks = {}
    for name, path in check_paths.items():
        failures = []
        for result in results:
            value = result
            for key in path:
                value = value.get(key, False) if isinstance(value, dict) else False
            if not value:
                failures.append(f"{result['key']}-{result['theme']}")
        checks[name] = {"pass": not failures, "failedScreens": failures}
    passed = sum(result["pass"] for result in results)
    report = {
        "schemaVersion": 1,
        "renderer": {"engine": "Chromium", "version": browser_version,
            "executable": str(args.chromium), "networkRequests": "blocked",
            "documentLoading": "Playwright set_content, unchanged HTML",
            "locale": "ru-RU", "timezone": "UTC", "colorProfile": "sRGB",
            "reducedMotion": True, "fontReadiness": "document.fonts.ready"},
        "viewport": {"width": PHONE_WIDTH, "height": PHONE_HEIGHT,
            "deviceScaleFactor": DEVICE_SCALE},
        "expectedScreenshot": {"width": PHONE_WIDTH * DEVICE_SCALE,
            "height": PHONE_HEIGHT * DEVICE_SCALE},
        "minimumTarget": {"width": MIN_TARGET, "height": MIN_TARGET},
        "summary": {"totalScreens": len(results), "passedScreens": passed,
            "failedScreens": len(results) - passed,
            "pass": passed == len(results) and board["pass"], "checks": checks},
        "board": board,
        "screens": results,
    }
    report_path = root / "render-report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")
    print(f"Rendered {len(results)} screens; {passed} passed, "
        f"{len(results) - passed} failed. Wrote board.png and render-report.json.")
    return 0 if report["summary"]["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
