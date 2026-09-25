#!/usr/bin/env python3
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate an AltStore/SideStore/LiveContainer source for LectureScan."
    )
    parser.add_argument("--output", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--size", required=True, type=int)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--date")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    released_at = args.date or datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    released_at = released_at.replace("+00:00", "Z")
    release_day = released_at[:10]
    repository_url = "https://github.com/nmt3325/LectureScan"
    icon_url = (
        "https://raw.githubusercontent.com/nmt3325/LectureScan/main/"
        "LectureScan/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    )
    description = (
        "授業中の書類・黒板・スクリーンを無音で撮影し、矩形補正した画像を"
        "写真ライブラリへ保存してクリップボードへ自動コピーします。"
    )
    release_description = f"main の {args.commit[:7]} から自動生成した未署名 IPA"
    privacy = {
        "NSCameraUsageDescription": "書類・黒板・スクリーンの撮影と矩形補正に使用します。",
        "NSPhotoLibraryAddUsageDescription": "補正済み画像を写真ライブラリへ保存します。",
    }

    version_entry = {
        "version": args.version,
        "buildNumber": str(args.build_number),
        "date": released_at,
        "localizedDescription": release_description,
        "downloadURL": args.download_url,
        "size": args.size,
        "minOSVersion": "17.0",
    }
    app = {
        "beta": True,
        "name": "LectureScan",
        "bundleIdentifier": "dev.nmt3325.LectureScan",
        "developerName": "沼田 開智",
        "subtitle": "授業向け無音ドキュメントカメラ",
        "version": args.version,
        "versionDate": release_day,
        "versionDescription": release_description,
        "downloadURL": args.download_url,
        "localizedDescription": description,
        "iconURL": icon_url,
        "tintColor": "#FFD60A",
        "category": "utilities",
        "size": args.size,
        "minOSVersion": "17.0",
        "appPermissions": {"entitlements": [], "privacy": privacy},
        "versions": [version_entry],
    }
    source = {
        "name": "LectureScan",
        "identifier": "dev.nmt3325.LectureScan.source",
        "subtitle": "LectureScan automated unsigned builds",
        "description": "AltStore・SideStore・LiveContainer 互換の公式ビルドソースです。",
        "website": repository_url,
        "iconURL": icon_url,
        "tintColor": "#FFD60A",
        "featuredApps": ["dev.nmt3325.LectureScan"],
        "apps": [app],
        "news": [],
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(source, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
