#!/usr/bin/env python3
"""Read-only identity checks for Orca Run and Dispatch receipts."""

import argparse
import json
import sys


class InvalidReceipt(ValueError):
    pass


def load_receipt(path):
    try:
        with open(path, encoding="utf-8") as stream:
            receipt = json.load(stream)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise InvalidReceipt("receipt を読み取れません") from error
    if not isinstance(receipt, dict) or receipt.get("ok") is not True:
        raise InvalidReceipt("receipt が成功応答ではありません")
    if receipt.get("error") is not None:
        raise InvalidReceipt("receipt に error があります")
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise InvalidReceipt("receipt に result がありません")
    return result


def require_match(actual, expected, label):
    if (
        not isinstance(actual, str)
        or not actual.strip()
        or not isinstance(expected, str)
        or not expected.strip()
        or actual != expected
    ):
        raise InvalidReceipt(f"{label} が期待値と一致しません")


def validate_coordinator(result, args):
    run = result.get("run")
    if not isinstance(run, dict):
        raise InvalidReceipt("result.run がありません")
    require_match(run.get("id"), args.run, "Run ID")
    require_match(run.get("coordinator_handle"), args.handle, "coordinator handle")


def validate_worker(result, args):
    dispatch = result.get("dispatch")
    if not isinstance(dispatch, dict):
        raise InvalidReceipt("result.dispatch がありません")
    require_match(dispatch.get("id"), args.dispatch, "Dispatch ID")
    require_match(dispatch.get("taskId"), args.task, "Task ID")
    require_match(dispatch.get("assigneeHandle"), args.assignee, "assignee handle")
    require_match(dispatch.get("status"), "dispatched", "Dispatch status")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="kind", required=True)
    coordinator = subparsers.add_parser("coordinator", help="validate a Run receipt")
    coordinator.add_argument("receipt")
    coordinator.add_argument("--run", required=True)
    coordinator.add_argument("--handle", required=True)
    worker = subparsers.add_parser("worker-show", help="validate a dispatched worker-show receipt")
    worker.add_argument("receipt")
    worker.add_argument("--dispatch", required=True)
    worker.add_argument("--task", required=True)
    worker.add_argument("--assignee", required=True)
    args = parser.parse_args(argv)

    try:
        result = load_receipt(args.receipt)
        if args.kind == "coordinator":
            validate_coordinator(result, args)
        else:
            validate_worker(result, args)
    except InvalidReceipt as error:
        print(f"preflight 拒否: {error}", file=sys.stderr)
        return 1

    print("preflight OK: receipt identity matches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
