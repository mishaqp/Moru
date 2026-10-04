#!/usr/bin/env python3
"""Print failed tests from a `flutter test --file-reporter json:` report.

The job log viewer only exposes the tail of a long test run, so a failure
early in the suite is otherwise invisible. This prints each failed test's
name, file, error and stack trace at the end of the job.
"""

import json
import sys


def main(path: str) -> int:
    tests = {}
    errors = {}
    failed = []
    try:
        with open(path, encoding="utf-8") as report:
            for line in report:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                kind = event.get("type")
                if kind == "testStart":
                    test = event.get("test", {})
                    tests[test.get("id")] = test
                elif kind == "error":
                    errors.setdefault(event.get("testID"), []).append(event)
                elif kind == "testDone":
                    if event.get("result") != "success" and not event.get("hidden"):
                        failed.append(event.get("testID"))
    except FileNotFoundError:
        print(f"No test report at {path}.")
        return 0

    if not failed:
        print("No failed tests in the report.")
        return 0
    for test_id in failed:
        test = tests.get(test_id, {})
        location = test.get("root_url") or test.get("url") or ""
        print(f"::error::FAILED {test.get('name', test_id)} ({location})")
        for error in errors.get(test_id, []):
            print(error.get("error", "").rstrip())
            print(error.get("stackTrace", "").rstrip())
        print("-" * 72)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
