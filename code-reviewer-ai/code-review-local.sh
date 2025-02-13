#!/bin/bash

pushd $(dirname $0) > /dev/null 2>&1 || exit 1
source ./venv/bin/activate

python code-review.py

popd

