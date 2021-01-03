#!/bin/bash

# Run this as sudo

set -Eeuo pipefail

(crontab -l ; echo "@hourly /home/algo/traffic-shaping/add-traffic-shaping.sh") | crontab -