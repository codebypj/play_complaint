#!/bin/bash

# Standalone Play Internet Summary Generator - wersja polska
# Użycie: ./generate_summary.sh [YYYY-MM-DD|all|last7|last30]
# Opcje:
#   all      - Generuj podsumowanie dla WSZYSTKICH dostępnych logów
#   last7    - Generuj podsumowanie dla ostatnich 7 dni
#   last30   - Generuj podsumowanie dla ostatnich 30 dni
#   YYYY-MM-DD - Generuj podsumowanie dla konkretnej daty
#   (brak argumentów) - Generuj podsumowanie dla wczoraj

LOG_DIR="$HOME/internet_logs"

# Funkcja do pozyskania wszystkich dostępnych dat z logów
get_available_dates() {
    find "$LOG_DIR" -name "speed_*.log" -o -name "ping_*.log" 2>/dev/null | \
        sed 's/.*_\([0-9]\{8\}\).*/\1/' | sort -u | \
        sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/'
}

# Funkcja do pozyskania dat w określonym zakresie
get_dates_in_range() {
    local days_back="$1"
    local dates=""
    for i in $(seq 0 $days_back); do
        local date=$(date -d "$i days ago" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d 2>/dev/null)
        dates="$dates $date"
    done
    echo $dates
}

# Funkcja do generowania kompleksowego podsumowania dla wielu dat
generate_comprehensive_summary() {
    local dates="$1"
    local summary_type="$2"
    local output_file="$LOG_DIR/podsumowanie_komprehensywne_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "Generuję kompleksowe podsumowanie dla $summary_type..."
    echo "Plik wynikowy: $output_file"
    
    {
        echo "=== KOMPLEKSOWE PODSUMOWANIE INTERNETU PLAY ==="
        echo "Typ: $summary_type"
        echo "Wygenerowane: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "System: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' || uname -s)"
        echo "Katalog logów: $LOG_DIR"
        echo ""
        
        # Policz łączną liczbę analizowanych dat
        local total_dates=$(echo $dates | wc -w)
        echo "=== PRZEGLĄD ==="
        echo "Analizowane daty: $total_dates"
        echo "Zakres dat: $(echo $dates | awk '{print $1}') do $(echo $dates | awk '{print $NF}')"
        echo ""
        
        # Ogólne statystyki
        echo "=== STATYSTYKI OGÓLNE ==="
        
        # Zbierz wszystkie dane o testach prędkości
        local all_speed_files=""
        local all_ping_files=""
        local dates_with_data=""
        
        for date in $dates; do
            local date_formatted="${date//-/}"
            local speed_files=$(find "$LOG_DIR" -name "speed_$date_formatted*.log" 2>/dev/null)
            local ping_files=$(find "$LOG_DIR" -name "ping_$date_formatted*.log" 2>/dev/null)
            
            if [ -n "$speed_files" ] || [ -n "$ping_files" ]; then
                dates_with_data="$dates_with_data $date"
                all_speed_files="$all_speed_files $speed_files"
                all_ping_files="$all_ping_files $ping_files"
            fi
        done
        
        echo "Daty z rzeczywistymi danymi: $(echo $dates_with_data | wc -w)"
        
        # Analiza testów prędkości
        if [ -n "$all_speed_files" ]; then
            local total_speed_tests=$(grep "Download:" $all_speed_files 2>/dev/null | wc -l)
            local slow_tests=$(grep "Download:" $all_speed_files 2>/dev/null | awk '$2 < 400' | wc -l)
            local very_slow_tests=$(grep "Download:" $all_speed_files 2>/dev/null | awk '$2 < 200' | wc -l)
            
            if [ $total_speed_tests -gt 0 ]; then
                local avg_speed=$(grep "Download:" $all_speed_files 2>/dev/null | awk '{sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
                local min_speed=$(grep "Download:" $all_speed_files 2>/dev/null | awk 'BEGIN{min=999999} {if($2<min) min=$2} END{print min}')
                local max_speed=$(grep "Download:" $all_speed_files 2>/dev/null | awk 'BEGIN{max=0} {if($2>max) max=$2} END{print max}')
                
                echo ""
                echo "PODSUMOWANIE TESTÓW PRĘDKOŚCI:"
                echo "  Łączna liczba testów: $total_speed_tests"
                echo "  Średnia prędkość: ${avg_speed} Mb/s"
                echo "  Minimalna prędkość: ${min_speed} Mb/s"
                echo "  Maksymalna prędkość: ${max_speed} Mb/s"
                echo "  Testy poniżej 400 Mb/s: $slow_tests ($(awk "BEGIN {printf \"%.1f\", $slow_tests * 100 / $total_speed_tests}")%)"
                echo "  Testy poniżej 200 Mb/s: $very_slow_tests ($(awk "BEGIN {printf \"%.1f\", $very_slow_tests * 100 / $total_speed_tests}")%)"
                
                if [ $slow_tests -gt 0 ]; then
                    echo "  ⚠ PROBLEM ZGODNOŚCI: $(awk "BEGIN {printf \"%.1f\", $slow_tests * 100 / $total_speed_tests}")% testów poniżej gwarantowanego minimum!"
                else
                    echo "  ✓ Wszystkie testy powyżej gwarantowanego minimum (400 Mb/s)"
                fi
            fi
        else
            echo "Brak danych testów prędkości"
        fi
        
        # Analiza testów ping
        if [ -n "$all_ping_files" ]; then
            local total_pings=$(grep "time=" $all_ping_files 2>/dev/null | wc -l)
            local timeouts=$(grep -E "(timeout|unreachable|100% packet loss)" $all_ping_files 2>/dev/null | wc -l)
            
            if [ $total_pings -gt 0 ]; then
                local success_rate=$(awk "BEGIN {printf \"%.3f\", ($total_pings - $timeouts) * 100 / $total_pings}")
                
                echo ""
                echo "PODSUMOWANIE STABILNOŚCI POŁĄCZENIA:"
                echo "  Łączna liczba pingów: $total_pings"
                echo "  Nieudane pingi: $timeouts"
                echo "  Wskaźnik sukcesu: ${success_rate}%"
                
                if [ $timeouts -eq 0 ]; then
                    echo "  ✓ Idealna stabilność połączenia"
                elif [ $(echo "$success_rate > 99" | bc -l) -eq 1 ]; then
                    echo "  ✓ Doskonała stabilność połączenia"
                elif [ $(echo "$success_rate > 95" | bc -l) -eq 1 ]; then
                    echo "  ⚠ Dobra stabilność połączenia"
                else
                    echo "  ⚠ PROBLEMY Z POŁĄCZENIEM: Wskaźnik sukcesu poniżej 95%"
                fi
            fi
        else
            echo "Brak danych testów ping"
        fi
        
        echo ""
        echo "=== ZESTAWIENIE DZIENNE ==="
        
        # Generuj podsumowanie dla każdej daty z danymi
        for date in $dates_with_data; do
            local date_formatted="${date//-/}"
            echo ""
            echo "--- $date ---"
            
            # Testy prędkości dla tej daty
            local speed_files=$(find "$LOG_DIR" -name "speed_$date_formatted*.log" 2>/dev/null)
            if [ -n "$speed_files" ]; then
                local daily_tests=$(grep "Download:" $speed_files 2>/dev/null | wc -l)
                local daily_slow=$(grep "Download:" $speed_files 2>/dev/null | awk '$2 < 400' | wc -l)
                local daily_avg=$(grep "Download:" $speed_files 2>/dev/null | awk '{sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
                
                echo "  Testy prędkości: $daily_tests, Śr.: ${daily_avg} Mb/s, Poniżej 400: $daily_slow"
            else
                echo "  Testy prędkości: Brak danych"
            fi
            
            # Testy ping dla tej daty
            local ping_files=$(find "$LOG_DIR" -name "ping_$date_formatted*.log" 2>/dev/null)
            if [ -n "$ping_files" ]; then
                local daily_pings=$(grep "time=" $ping_files 2>/dev/null | wc -l)
                local daily_timeouts=$(grep -E "(timeout|unreachable|100% packet loss)" $ping_files 2>/dev/null | wc -l)
                local daily_success=0
                if [ $daily_pings -gt 0 ]; then
                    daily_success=$(awk "BEGIN {printf \"%.1f\", ($daily_pings - $daily_timeouts) * 100 / $daily_pings}")
                fi
                
                echo "  Połączenie: $daily_pings pingów, ${daily_success}% sukces, $daily_timeouts niepowodzeń"
            else
                echo "  Połączenie: Brak danych"
            fi
        done
        
        echo ""
        echo "=== ANALIZA PROBLEMÓW ==="
        
        # Znajdź najgorsze dni pod względem wydajności
        echo ""
        echo "NAJGORSZE DNI POD WZGLĘDEM PRĘDKOŚCI:"
        for date in $dates_with_data; do
            local date_formatted="${date//-/}"
            local speed_files=$(find "$LOG_DIR" -name "speed_$date_formatted*.log" 2>/dev/null)
            if [ -n "$speed_files" ]; then
                local daily_avg=$(grep "Download:" $speed_files 2>/dev/null | awk '{sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
                echo "$date $daily_avg"
            fi
        done | sort -k2 -n | head -5 | while read date speed; do
            echo "  $date: ${speed} Mb/s średnio"
        done
        
        echo ""
        echo "DNI Z PROBLEMAMI POŁĄCZENIA:"
        for date in $dates_with_data; do
            local date_formatted="${date//-/}"
            local ping_files=$(find "$LOG_DIR" -name "ping_$date_formatted*.log" 2>/dev/null)
            if [ -n "$ping_files" ]; then
                local daily_pings=$(grep "time=" $ping_files 2>/dev/null | wc -l)
                local daily_timeouts=$(grep -E "(timeout|unreachable|100% packet loss)" $ping_files 2>/dev/null | wc -l)
                if [ $daily_pings -gt 0 ] && [ $daily_timeouts -gt 0 ]; then
                    local failure_rate=$(awk "BEGIN {printf \"%.1f\", $daily_timeouts * 100 / $daily_pings}")
                    echo "$date $failure_rate $daily_timeouts"
                fi
            fi
        done | sort -k2 -nr | head -5 | while read date rate failures; do
            echo "  $date: ${rate}% niepowodzeń ($failures niepowodzeń)"
        done
        
        # Ostatnie problemy
        if [ -f "$LOG_DIR/monitor.log" ]; then
            echo ""
            echo "OSTATNIE BŁĘDY/PROBLEMY:"
            tail -100 "$LOG_DIR/monitor.log" | grep -i "error\|fail\|błąd\|problem" | tail -10 | while read line; do
                echo "  $line"
            done
        fi
        
        echo ""
        echo "=== OCENA ZGODNOŚCI Z REGULAMINEM ==="
        echo "Zgodnie z Regulaminem Play §6 ust. 23:"
        echo ""
        
        if [ -n "$all_speed_files" ] && [ $total_speed_tests -gt 0 ]; then
            local compliance_rate=$(awk "BEGIN {printf \"%.1f\", ($total_speed_tests - $slow_tests) * 100 / $total_speed_tests}")
            echo "Zgodność prędkości: ${compliance_rate}% testów spełnia gwarantowane minimum"
            if [ $slow_tests -eq 0 ]; then
                echo "✓ ZGODNE: Wszystkie testy prędkości powyżej 400 Mb/s"
            else
                echo "⚠ POTENCJALNY PROBLEM: $slow_tests testów poniżej gwarantowanego minimum"
            fi
        fi
        
        if [ -n "$all_ping_files" ] && [ $total_pings -gt 0 ]; then
            echo "Stabilność połączenia: ${success_rate}% czasu aktywności"
            if [ $timeouts -eq 0 ]; then
                echo "✓ DOSKONALE: Nie wykryto awarii połączenia"
            elif [ $(echo "$success_rate > 99" | bc -l) -eq 1 ]; then
                echo "✓ DOBRZE: Minimalne problemy z połączeniem"
            else
                echo "⚠ PROBLEMY: Stabilność połączenia może być poniżej oczekiwań"
            fi
        fi
        
        echo ""
        echo "=== REKOMENDACJE ==="
        
        if [ $slow_tests -gt 0 ]; then
            echo "• Skontaktuj się z obsługą Play w sprawie problemów z prędkością (dołącz ten raport)"
            echo "• Zażądaj inspekcji technicznej zgodnie z warunkami gwarancji usługi"
        fi
        
        if [ $timeouts -gt 0 ]; then
            echo "• Udokumentuj problemy ze stabilnością połączenia z czasem występowania"
            echo "• Najpierw sprawdź lokalne problemy sieciowe"
        fi
        
        if [ $total_speed_tests -eq 0 ] && [ $total_pings -eq 0 ]; then
            echo "• Nie znaleziono danych monitoringu - upewnij się, że skrypt monitorujący działa"
            echo "• Sprawdź katalog logów: $LOG_DIR"
        fi
        
        echo ""
        echo "Raport wygenerowany: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Okres danych: $summary_type"
        echo "Łączna liczba przeanalizowanych sesji monitoringu: $(echo $dates_with_data | wc -w) dni"
        
    } > "$output_file"
    
    echo ""
    echo "Kompleksowe podsumowanie wygenerowane: $output_file"
    echo ""
    echo "=== PODGLĄD PODSUMOWANIA ==="
    head -50 "$output_file"
    echo ""
    echo "... (pełny raport zapisany do pliku)"
    echo ""
    echo "Aby wyświetlić kompletny raport: cat \"$output_file\""
}

# Funkcja do generowania podsumowania dla konkretnej daty
generate_single_date_summary() {
    local target_date="$1"
    local date_formatted="${target_date//-/}"  # Konwertuj YYYY-MM-DD na YYYYMMDD
    local summary_file="$LOG_DIR/summary_$date_formatted.txt"
    
    echo "Generuję podsumowanie dla $target_date..."
    
    # Sprawdź czy katalog logów istnieje
    if [ ! -d "$LOG_DIR" ]; then
        echo "BŁĄD: Katalog logów $LOG_DIR nie został znaleziony!"
        echo "Upewnij się, że skrypt monitorujący działa."
        exit 1
    fi
    
    {
        echo "=== PODSUMOWANIE DNIA $date_formatted ==="
        echo "Data: $target_date"
        echo "Wygenerowano: $(date)"
        echo "System: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' || uname -s)"
        echo ""
        
        # Znajdź pliki testów prędkości dla tej daty
        local speed_files=$(find "$LOG_DIR" -name "speed_$date_formatted*.log" 2>/dev/null)
        
        echo "=== TESTY PRĘDKOŚCI ==="
        if [ -n "$speed_files" ] && [ -f $(echo $speed_files | cut -d' ' -f1) ]; then
            # Policz łączną liczbę testów
            local total_tests=$(grep "Download:" $speed_files 2>/dev/null | wc -l)
            
            if [ $total_tests -gt 0 ]; then
                # Policz wolne testy (poniżej 400 Mb/s)
                local slow_tests=$(grep "Download:" $speed_files 2>/dev/null | awk '$2 < 400' | wc -l)
                
                # Oblicz średnią prędkość
                local avg_speed=$(grep "Download:" $speed_files 2>/dev/null | awk '{sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
                
                echo "Łączna liczba testów: $total_tests"
                echo "Testy poniżej 400 Mb/s: $slow_tests"
                echo "Średnia prędkość: ${avg_speed} Mb/s"
                
                if [ $slow_tests -gt 0 ]; then
                    local percentage=$(awk "BEGIN {printf \"%.1f\", $slow_tests * 100 / $total_tests}")
                    echo "⚠ PROBLEM: ${percentage}% testów poniżej gwarantowanego minimum!"
                fi
            else
                echo "Brak poprawnych danych o prędkości w plikach testów"
            fi
        else
            echo "Brak plików z testami prędkości dla daty $target_date"
        fi
        
        echo ""
        
        # Znajdź pliki testów ping dla tej daty
        local ping_files=$(find "$LOG_DIR" -name "ping_$date_formatted*.log" 2>/dev/null)
        
        echo "=== STABILNOŚĆ POŁĄCZENIA ==="
        if [ -n "$ping_files" ] && [ -f $(echo $ping_files | cut -d' ' -f1) ]; then
            # Policz timeouty i udane pingi
            local timeouts=$(grep -E "(timeout|unreachable|100% packet loss)" $ping_files 2>/dev/null | wc -l)
            local total_pings=$(grep "time=" $ping_files 2>/dev/null | wc -l)
            
            echo "Łączna liczba pingów: $total_pings"
            echo "Przerwy/timeouty: $timeouts"
            
            if [ $total_pings -gt 0 ]; then
                local success_rate=$(awk "BEGIN {printf \"%.2f\", ($total_pings - $timeouts) * 100 / $total_pings}")
                echo "Dostępność: ${success_rate}%"
                
                if [ $timeouts -gt 0 ]; then
                    echo "⚠ PROBLEM: Wykryto $timeouts przerw w połączeniu!"
                fi
            else
                echo "Brak danych o pingach"
            fi
        else
            echo "Brak plików z testami ping dla daty $target_date"
        fi
        
        echo ""
        echo "Zgodnie z Regulaminem Play §6 ust. 23"
        echo "Raport wygenerowany: $(date '+%Y-%m-%d %H:%M:%S')"
        
    } > "$summary_file"
    
    echo "Podsumowanie wygenerowane: $summary_file"
    echo ""
    echo "=== PODGLĄD PODSUMOWANIA ==="
    cat "$summary_file"
}

# Główna logika skryptu
main() {
    local option="$1"
    
    # Sprawdź czy katalog logów istnieje
    if [ ! -d "$LOG_DIR" ]; then
        echo "BŁĄD: Katalog logów $LOG_DIR nie został znaleziony!"
        echo "Upewnij się, że skrypt monitorujący działa."
        exit 1
    fi
    
    case "$option" in
        "all")
            local all_dates=$(get_available_dates)
            if [ -z "$all_dates" ]; then
                echo "Nie znaleziono plików logów w $LOG_DIR"
                exit 1
            fi
            generate_comprehensive_summary "$all_dates" "WSZYSTKIE DOSTĘPNE DANE"
            ;;
        "last7")
            local recent_dates=$(get_dates_in_range 6)  # 0-6 = 7 dni
            generate_comprehensive_summary "$recent_dates" "OSTATNIE 7 DNI"
            ;;
        "last30")
            local recent_dates=$(get_dates_in_range 29)  # 0-29 = 30 dni
            generate_comprehensive_summary "$recent_dates" "OSTATNIE 30 DNI"
            ;;
        "")
            # Brak argumentu - użyj wczoraj
            local yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -d "-1 day" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
            echo "Nie podano opcji, generuję podsumowanie dla wczoraj: $yesterday"
            generate_single_date_summary "$yesterday"
            ;;
        *)
            # Sprawdź czy to format daty
            if date -d "$option" >/dev/null 2>&1; then
                generate_single_date_summary "$option"
            else
                echo "BŁĄD: Nieprawidłowa opcja '$option'"
                echo "Prawidłowe opcje: all, last7, last30, lub data w formacie YYYY-MM-DD"
                exit 1
            fi
            ;;
    esac
}

# Pokaż pomoc jeśli --help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Generator Kompleksowych Podsumowań Internetu Play"
    echo ""
    echo "Użycie: $0 [opcja]"
    echo ""
    echo "Opcje:"
    echo "  all              Generuj kompleksowe podsumowanie dla WSZYSTKICH dostępnych logów"
    echo "  last7            Generuj podsumowanie dla ostatnich 7 dni"
    echo "  last30           Generuj podsumowanie dla ostatnich 30 dni"
    echo "  YYYY-MM-DD       Generuj podsumowanie dla konkretnej daty"
    echo "  (brak argumentów) Generuj podsumowanie dla wczoraj"
    echo ""
    echo "Przykłady:"
    echo "  $0 all                    # Analizuj wszystkie dostępne dane"
    echo "  $0 last7                  # Podsumowanie ostatnich 7 dni"
    echo "  $0 last30                 # Podsumowanie ostatnich 30 dni"
    echo "  $0 2025-01-25            # Konkretna data"
    echo "  $0                       # Tylko wczoraj"
    echo ""
    echo "Dostępne daty z logami:"
    get_available_dates | head -10
    echo ""
    exit 0
fi

# Uruchom główną funkcję
main "$1"
