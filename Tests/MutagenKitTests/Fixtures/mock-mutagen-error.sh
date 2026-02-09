#!/bin/bash
# ABOUTME: Mock script simulating mutagen CLI error responses.
# ABOUTME: Always returns non-zero exit code with error message on stderr.

echo "Error: daemon not running" >&2
exit 1
