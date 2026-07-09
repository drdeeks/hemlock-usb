## Daily Cron Job for Skills Update Inside Container

### pull-drdeeks-daily.sh
```bash
#!/bin/bash
# Daily pull of drdeeks skills repo - runs inside container
# Keeps skills up to date on the portable USB

set -e
SKILLS_DIR="/home/ubuntu/hemlock-minimal/hemlock-minimal/skills/drdeeks"
LOG_FILE="/var/log/drdeeks-pull.log"

echo "[$(date)] Starting drdeeks skills pull" >> $LOG_FILE

if [ -d "$SKILLS_DIR/.git" ]; then
    cd "$SKILLS_DIR"
    git pull origin main 2>&1 | tee -a $LOG_FILE
else
    git clone --depth 1 https://github.com/drdeeks/skills.git "$SKILLS_DIR" 2>&1 | tee -a $LOG_FILE
fi

echo "[$(date)] drdeeks skills update finished" >> $LOG_FILE
```

### Crontab Entry (Inside Container)
```bash
0 2 * * * /home/ubuntu/hemlock-minimal/scripts/pull-drdeeks-daily.sh >> /var/log/drdeeks-cron.log 2>&1
```

### Container Init Script
```bash
#!/bin/bash
# Runs on container startup via entrypoint.sh

# Install cron if missing
if ! command -v cron &> /dev/null; then
    apt-get update && apt-get install -y cron
fi

# Add daily pull to crontab
CRON_JOB="0 2 * * * /home/ubuntu/hemlock-minimal/scripts/pull-drdeeks-daily.sh >> /var/log/drdeeks-cron.log 2>&1"
if ! crontab -l 2>/dev/null | grep -q "pull-drdeeks-daily.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
fi

# Start cron daemon
service cron start
```

