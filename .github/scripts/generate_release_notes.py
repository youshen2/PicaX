#!/usr/bin/env python3

"""Generate metadata for the Markdown release notes bundled with PicaX."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


def git(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *arguments],
        check=check,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def resolve_commit(reference: str) -> str:
    result = git(
        "rev-parse",
        "--verify",
        f"{reference}^{{commit}}",
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"无法解析 Commit 或标签：{reference}")
    return result.stdout.strip()


def is_ancestor(reference: str, current_commit: str) -> bool:
    return (
        git(
            "merge-base",
            "--is-ancestor",
            reference,
            current_commit,
            check=False,
        ).returncode
        == 0
    )


def exact_version_tag(current_commit: str, current_reference: str) -> str | None:
    tags = git(
        "tag",
        "--points-at",
        current_commit,
        "--list",
        "v*",
        "--sort=-version:refname",
    ).stdout.splitlines()
    if not tags:
        return None

    reference_name = current_reference.removeprefix("refs/tags/")
    if reference_name in tags:
        return reference_name
    return tags[0]


def infer_previous_version_tag(
    current_commit: str,
    current_tag: str | None,
) -> str | None:
    reference = f"{current_commit}^" if current_tag is not None else current_commit
    result = git(
        "describe",
        "--tags",
        "--match",
        "v*",
        "--abbrev=0",
        reference,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def version_label(reference: str | None) -> str | None:
    if reference is None:
        return None
    reference_name = reference.removeprefix("refs/tags/")
    if len(reference_name) > 1 and reference_name[0].lower() == "v":
        return reference_name[1:]
    return reference_name


def validate_release_notes(path: Path) -> int:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise ValueError(f"无法读取更新日志 {path}：{error}") from error

    if not lines:
        raise ValueError(f"更新日志不能为空：{path}")

    for line_number, line in enumerate(lines, start=1):
        stripped_line = line.strip()
        if not stripped_line.startswith("- ") or not stripped_line[2:].strip():
            raise ValueError(
                f"更新日志第 {line_number} 行必须是单条 Markdown 列表项"
            )
    return len(lines)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current-ref", default="HEAD")
    parser.add_argument("--previous-ref")
    parser.add_argument("--version", required=True)
    parser.add_argument("--notes", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()

    try:
        current_commit = resolve_commit(arguments.current_ref)
        current_tag = exact_version_tag(current_commit, arguments.current_ref)
        previous_reference = arguments.previous_ref or infer_previous_version_tag(
            current_commit,
            current_tag,
        )

        if previous_reference is not None:
            resolve_commit(previous_reference)
            if not is_ancestor(previous_reference, current_commit):
                raise ValueError(
                    f"更新日志基线 {previous_reference} 不是当前 Commit 的祖先"
                )

        entry_count = validate_release_notes(arguments.notes)
    except (subprocess.CalledProcessError, ValueError) as error:
        print(f"生成更新日志失败：{error}", file=sys.stderr)
        return 1

    payload = {
        "schemaVersion": 2,
        "version": arguments.version.removeprefix("v"),
        "sourceRevision": current_commit,
        "currentRef": current_tag or arguments.current_ref,
        "previousRef": previous_reference,
        "previousVersion": version_label(previous_reference),
    }

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    temporary_output = arguments.output.with_suffix(
        f"{arguments.output.suffix}.tmp"
    )
    temporary_output.write_text(
        f"{json.dumps(payload, ensure_ascii=False, indent=2)}\n",
        encoding="utf-8",
    )
    temporary_output.replace(arguments.output)

    range_description = (
        f"{previous_reference}..{current_tag or current_commit[:7]}"
        if previous_reference is not None
        else "无可用的历史版本基线"
    )
    print(
        f"已生成 PicaX {payload['version']} 更新日志："
        f"{range_description}，从 {arguments.notes} 读取 {entry_count} 条"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
