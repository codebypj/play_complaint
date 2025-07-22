# Nadaj uprawnienia
chmod +x speed_test.sh

# Test czy działa
./speed_test.sh

# Uruchom w tle
nohup ./speed_test.sh > /dev/null 2>&1 &

# Sprawdź logi
tail -f ~/internet_logs/monitor.log

# Zobacz ostatnie testy
ls -la ~/internet_logs/

# Sprawdź podsumowanie
cat ~/internet_logs/summary_$(date +%Y%m%d).txt
