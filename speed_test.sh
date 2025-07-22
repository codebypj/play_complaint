#!/bin/bash
LOG_DIR="$HOME/internet_logs"
MAX_LOG_DAYS=30
SPEED_TEST_INTERVAL=7200  # Co 2h
PING_TEST_DURATION=300
PING_INTERVAL=10

# Sprawdź czy już działa
PIDFILE="$LOG_DIR/monitor.pid"
if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
    echo "Monitor już działa (PID: $(cat $PIDFILE))"
    exit 1
fi

# Tworzenie katalogów
mkdir -p "$LOG_DIR"
echo $$ > "$PIDFILE"

# Funkcja czyszczenia
cleanup() {
    echo "$(date): Zatrzymywanie monitora..." >> "$LOG_DIR/monitor.log"
    rm -f "$PIDFILE"
    exit 0
}

# Rotacja logów
rotate_logs() {
    find "$LOG_DIR" -name "*.log" -mtime +$MAX_LOG_DAYS -delete
    find "$LOG_DIR" -name "*.txt" -mtime +$MAX_LOG_DAYS -delete
}

# Informacje o systemie
system_info() {
    local info_file="$LOG_DIR/system_info_$(date +%Y%m%d).txt"
    
    if [ ! -f "$info_file" ]; then
        {
            echo "=== INFORMACJE O SYSTEMIE ==="
            echo "Data: $(date)"
            echo "System: $(uname -a)"
            echo "Dystrybucja: $(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"' || uname -s)"
            echo ""
            
            # Karta sieciowa
            echo "=== KARTA SIECIOWA ==="
            lspci | grep -i ethernet || echo "Nie znaleziono karty Ethernet"
            
            # Interfejs sieciowy
            local interface=$(ip route | grep default | awk '{print $5}' | head -1)
            echo "Główny interfejs: $interface"
            
            if [ -n "$interface" ]; then
                echo "Status interfejsu:"
                ip link show "$interface" 2>/dev/null || echo "Nie można odczytać statusu"
                
                # Prędkość łącza (jeśli dostępne)
                ethtool "$interface" 2>/dev/null | grep Speed || echo "Prędkość: Nie można odczytać"
            fi
            
            echo ""
            echo "=== ROUTING ==="
            ip route 2>/dev/null || echo "Błąd odczytu routingu"
            
            echo ""
            echo "=== DNS ==="
            cat /etc/resolv.conf 2>/dev/null || echo "Nie można odczytać DNS"
            
        } > "$info_file"
    fi
}

# Sprawdź warunki pomiarowe
check_measurement_conditions() {
    local conditions_file="$LOG_DIR/conditions_$(date +%Y%m%d_%H%M%S).log"
    
    {
        echo "=== WERYFIKACJA WARUNKÓW POMIAROWYCH ==="
        echo "Zgodnie z Regulaminem Play §6 ust. 23"
        echo "Data: $(date)"
        echo ""
        
        # Sprawdź główny interfejs
        local interface=$(ip route | grep default | awk '{print $5}' | head -1)
        echo "Główny interfejs: $interface"
        
        if [[ $interface =~ ^(eth|enp|eno) ]]; then
            echo "✓ Połączenie kablowe: TAK"
        else
            echo "⚠ Połączenie: $interface (może być WiFi)"
        fi
        
        # Sprawdź gateway
        local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
        echo "Gateway Play: $gateway"
        
        # Test ping do gateway
        if [ -n "$gateway" ]; then
            local gateway_ping=$(ping -c 1 -W 2 "$gateway" 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
            if [ -n "$gateway_ping" ]; then
                echo "✓ Ping do gateway: ${gateway_ping}ms"
            else
                echo "✗ Brak odpowiedzi od gateway"
            fi
        fi
        
        echo ""
        
    } >> "$conditions_file"
}

# Test prędkości zgodny z regulaminem
speed_test_compliant() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local speed_file="$LOG_DIR/speed_$timestamp.log"
    
    echo "$(date): Rozpoczynam test prędkości..." >> "$LOG_DIR/monitor.log"
    
    # Sprawdź czy speedtest-cli jest dostępne
    if ! command -v speedtest-cli &> /dev/null; then
        echo "$(date): BŁĄD - speedtest-cli nie jest zainstalowane!" >> "$LOG_DIR/monitor.log"
        echo "Zainstaluj: użyj menedżera pakietów swojej dystrybucji (np. sudo apt install speedtest-cli lub sudo dnf install speedtest-cli)" >> "$LOG_DIR/monitor.log"
        return 1
    fi
    
    {
        echo "=== SPEEDTEST ZGODNY Z REGULAMINEM PLAY ==="
        echo "§6 ust. 23 - warunki pomiarowe"
        echo "Data: $(date)"
        echo ""
        
        # Warunki pomiarowe
        check_measurement_conditions
        
        echo "=== POMIAR PRĘDKOŚCI ==="
        # Test z timeoutem i obsługą błędów
        timeout 120 speedtest-cli --simple --secure 2>&1
        local exit_code=$?
        echo "Status testu: $exit_code"
        
        if [ $exit_code -ne 0 ]; then
            echo "BŁĄD: Test prędkości nie powiódł się (kod: $exit_code)"
        fi
        
        echo ""
        echo "=== INFORMACJE TECHNICZNE ==="
        echo "Interfejs: $(ip route | grep default | awk '{print $5}' | head -1)"
        echo "Gateway: $(ip route | grep default | awk '{print $3}' | head -1)"
        echo "Czas: $(date '+%Y-%m-%d %H:%M:%S')"
        
    } >> "$speed_file"
}

# Test stabilności połączenia
ping_test() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local ping_file="$LOG_DIR/ping_$timestamp.log"
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    
    echo "$(date): Rozpoczynam test ping ($PING_TEST_DURATION s)..." >> "$LOG_DIR/monitor.log"
    
    {
        echo "=== TEST STABILNOŚCI POŁĄCZENIA ==="
        echo "Data: $(date)"
        echo "Czas trwania: $PING_TEST_DURATION sekund"
        echo ""
        
        if [ -n "$gateway" ]; then
            echo "=== PING DO GATEWAY PLAY ($gateway) ==="
            timeout $((PING_TEST_DURATION/2)) ping -i $PING_INTERVAL "$gateway" | while read pong; do
                echo "$(date '+%Y-%m-%d %H:%M:%S') [GATEWAY]: $pong"
            done
            echo ""
        fi
        
        echo "=== PING KONTROLNY (8.8.8.8) ==="
        timeout $((PING_TEST_DURATION/2)) ping -i $PING_INTERVAL 8.8.8.8 | while read pong; do
            echo "$(date '+%Y-%m-%d %H:%M:%S') [EXTERNAL]: $pong"
        done
        
    } >> "$ping_file" 2>&1
}

# Generowanie podsumowania dziennego
generate_daily_summary() {
    local today=$(date +%Y%m%d)
    local summary_file="$LOG_DIR/summary_$today.txt"
    
    {
        echo "=== PODSUMOWANIE DNIA $today ==="
        echo "System: $(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"' || uname -s)"
        echo ""
        
        # Statystyki prędkości
        echo "=== TESTY PRĘDKOŚCI ==="
        local speed_files=$(find "$LOG_DIR" -name "speed_$today*.log" 2>/dev/null)
        if [ -n "$speed_files" ] && [ -f $speed_files ]; then
            local slow_tests=$(grep "Download:" $speed_files 2>/dev/null | awk '$2 < 400' | wc -l)
            local total_tests=$(grep "Download:" $speed_files 2>/dev/null | wc -l)
            
            if [ $total_tests -gt 0 ]; then
                local avg_speed=$(grep "Download:" $speed_files 2>/dev/null | awk '{sum+=$2; count++} END {if(count>0) print sum/count; else print 0}')
                echo "Łączna liczba testów: $total_tests"
                echo "Testy poniżej 400 Mb/s: $slow_tests"
                echo "Średnia prędkość: ${avg_speed} Mb/s"
                
                if [ $slow_tests -gt 0 ]; then
                    echo "⚠ PROBLEM: $(echo "scale=1; $slow_tests * 100 / $total_tests" | bc -l)% testów poniżej gwarantowanego minimum!"
                fi
            else
                echo "Brak poprawnych danych o prędkości"
            fi
        else
            echo "Brak plików z testami prędkości"
        fi
        
        echo ""
        
        # Statystyki ping
        echo "=== STABILNOŚĆ POŁĄCZENIA ==="
        local ping_files=$(find "$LOG_DIR" -name "ping_$today*.log" 2>/dev/null)
        if [ -n "$ping_files" ] && [ -f $ping_files ]; then
            local timeouts=$(grep -E "(timeout|unreachable|100% packet loss)" $ping_files 2>/dev/null | wc -l)
            local total_pings=$(grep "time=" $ping_files 2>/dev/null | wc -l)
            
            echo "Łączna liczba pingów: $total_pings"
            echo "Przerwy/timeouty: $timeouts"
            
            if [ $total_pings -gt 0 ]; then
                local success_rate=$(echo "scale=2; ($total_pings - $timeouts) * 100 / $total_pings" | bc -l)
                echo "Dostępność: ${success_rate}%"
                
                if [ $timeouts -gt 0 ]; then
                    echo "⚠ PROBLEM: Wykryto $timeouts przerw w połączeniu!"
                fi
            fi
        else
            echo "Brak danych o stabilności"
        fi
        
        echo ""
        echo "Wygenerowano: $(date)"
        
    } > "$summary_file"
}

# Obsługa sygnałów
trap cleanup SIGTERM SIGINT

echo "$(date): Uruchamianie monitora internetu Play..." >> "$LOG_DIR/monitor.log"
echo "PID: $$" >> "$LOG_DIR/monitor.log"
echo "System: $(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"' || uname -s)" >> "$LOG_DIR/monitor.log"

# Sprawdź narzędzia
if ! command -v speedtest-cli &> /dev/null; then
    echo "BŁĄD: speedtest-cli nie jest zainstalowane!"
    echo "Zainstaluj: użyj menedżera pakietów swojej dystrybucji (np. sudo apt install speedtest-cli lub sudo dnf install speedtest-cli)"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo "BŁĄD: bc nie jest zainstalowane!"
    echo "Zainstaluj: użyj menedżera pakietów swojej dystrybucji (np. sudo apt install bc lub sudo dnf install bc)"
    exit 1
fi

# Główna pętla
while true; do
    # Rotacja logów (raz dziennie o północy)
    if [ "$(date +%H%M)" == "0000" ]; then
        rotate_logs
        generate_daily_summary
    fi
    
    # Dokumentuj system
    system_info
    
    # Test prędkości
    speed_test_compliant
    
    # Test stabilności
    ping_test
    
    echo "$(date): Czekam $SPEED_TEST_INTERVAL sekund do następnego cyklu..." >> "$LOG_DIR/monitor.log"
    sleep $SPEED_TEST_INTERVAL
done
