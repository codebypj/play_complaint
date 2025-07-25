#!/bin/bash

# Standalone Play Internet Summary Generator
# Usage: ./generate_summary.sh [YYYY-MM-DD|all|last7|last30]
# Options:
#   all      - Generate summary for ALL available logs
#   last7    - Generate summary for last 7 days
#   last30   - Generate summary for last 30 days
#   YYYY-MM-DD - Generate summary for specific date
#   (no args) - Generate summary for yesterday

LOG_DIR="$HOME/internet_logs"

# Function to get all available dates from logs
get_available_dates() {
    find "$LOG_DIR" -name "speed_*.log" -o -name "ping_*.log" 2>/dev/null | \
        sed 's/.*_\([0-9]\{8\}\).*/\1/' | sort -u | \
        sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/'
}

# Function to get dates in range
get_dates_in_range() {
    local days_back="$1"
    local dates=""
    for i in $(seq 0 $days_back); do
        local date=$(date -d "$i days ago" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d 2>/dev/null)
        dates="$dates $date"
    done
    echo $dates
}

# Function to generate summary for multiple dates
generate_comprehensive_summary() {
    local dates="$1"
    local summary_type="$2"
    local output_file="$LOG_DIR/comprehensive_summary_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "Generating comprehensive summary for $summary_type..."
    echo "Output file: $output_file"
    
    {
        echo "=== COMPREHENSIVE PLAY INTERNET SUMMARY ==="
        echo "Type: $summary_type"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "System: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' || uname -s)"
        echo "Log Directory: $LOG_DIR"
        echo ""
        
        # Count total dates analyzed
        local total_dates=$(echo $dates | wc -w)
        echo "=== OVERVIEW ==="
        echo "Dates analyzed: $total_dates"
        echo "Date range: $(echo $dates | awk '{print $1}') to $(echo $dates | awk '{print $NF}')"
        echo ""
        
        # Overall statistics
        echo "=== OVERALL STATISTICS ==="
        
        # Collect all speed test data
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
        
        echo "Dates with actual data: $(echo $dates_with_data | wc -w)"
        
        # Speed test analysis
        if [ -n "$all_speed_files" ]; then
            local total_speed_tests=$(grep "Download:" $all_speed_files 2>/dev/null | wc -l)
            local slow_tests=$(grep "Download:" $all_speed_files 2>/dev/null | awk '$2 < 400' | wc -l)
            local very_slow_tests=$(grep "Download:" $all_speed_files 2>/dev/null | awk '$2 < 200' | wc -l)
            
            if [ $total_speed_tests -gt 0 ]; then
                local avg_speed=$(grep "Download:" $all_speed_files 2>/dev/null | awk '{sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
                local min_speed=$(grep "Download:" $all_speed_files 2>/dev/null | awk 'BEGIN{min=999999} {if($2<min) min=$2} END{print min}')
                local max_speed=$(grep "Download:" $all_speed_files 2>/dev/null | awk 'BEGIN{max=0} {if($2>max) max=$2} END{print max}')
                
                echo ""
                echo "SPEED TEST SUMMARY:"
                echo "  Total tests: $total_speed_tests"
                echo "  Average speed: ${avg_speed} Mb/s"
                echo "  Minimum speed: ${min_speed} Mb/s"
                echo "  Maximum speed: ${max_speed} Mb/s"
                echo "  Tests below 400 Mb/s: $slow_tests ($(awk "BEGIN {printf \"%.1f\", $slow_tests * 100 / $total_speed_tests}")%)"
                echo "  Tests below 200 Mb/s: $very_slow_tests ($(awk "BEGIN {printf \"%.1f\", $very_slow_tests * 100 / $total_speed_tests}")%)"
                
                if [ $slow_tests -gt 0 ]; then
                    echo "  ⚠ COMPLIANCE ISSUE: $(awk "BEGIN {printf \"%.1f\", $slow_tests * 100 / $total_speed_tests}")% tests below guaranteed minimum!"
                else
                    echo "  ✓ All tests above guaranteed minimum (400 Mb/s)"
                fi
            fi
        else
            echo "No speed test data found"
        fi
        
        # Ping test analysis
        if [ -n "$all_ping_files" ]; then
            local total_pings=$(grep "time=" $all_ping_files 2>/dev/null | wc -l)
            local timeouts=$(grep -E "(timeout|unreachable|100% packet loss)" $all_ping_files 2>/dev/null | wc -l)
            
            if [ $total_pings -gt 0 ]; then
                local success_rate=$(awk "BEGIN {printf \"%.3f\", ($total_pings - $timeouts) * 100 / $total_pings}")
                
                echo ""
                echo "CONNECTION STABILITY SUMMARY:"
                echo "  Total pings: $total_pings"
                echo "  Failed pings: $timeouts"
                echo "  Success rate: ${success_rate}%"
                
                if [ $timeouts -eq 0 ]; then
                    echo "  ✓ Perfect connection stability"
                elif [ $(echo "$success_rate > 99" | bc -l) -eq 1 ]; then
                    echo "  ✓ Excellent connection stability"
                elif [ $(echo "$success_rate > 95" | bc -l) -eq 1 ]; then
                    echo "  ⚠ Good connection stability"
                else
                    echo "  ⚠ CONNECTION ISSUES: Success rate below 95%"
                fi
            fi
        else
            echo "No ping test data found"
        fi
        
        echo ""
        echo "=== DAILY BREAKDOWN ==="
        
        # Generate summary for each date with data
        for date in $dates_with_data; do
            local date_formatted="${date//-/}"
            echo ""
            echo "--- $date ---"
            
            # Speed tests for this date
            local speed_files=$(find "$LOG_DIR" -name "speed_$date_formatted*.log" 2>/dev/null)
            if [ -n "$speed_files" ]; then
                local daily_tests=$(grep "Download:" $speed_files 2>/dev/null | wc -l)
                local daily_slow=$(grep "Download:" $speed_files 2>/dev/null | awk '$2 < 400' | wc -l)
                local daily_avg=$(grep "Download:" $speed_files 2>/dev/null | awk '{sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
                
                echo "  Speed tests: $daily_tests, Avg: ${daily_avg} Mb/s, Below 400: $daily_slow"
            else
                echo "  Speed tests: No data"
            fi
            
            # Ping tests for this date
            local ping_files=$(find "$LOG_DIR" -name "ping_$date_formatted*.log" 2>/dev/null)
            if [ -n "$ping_files" ]; then
                local daily_pings=$(grep "time=" $ping_files 2>/dev/null | wc -l)
                local daily_timeouts=$(grep -E "(timeout|unreachable|100% packet loss)" $ping_files 2>/dev/null | wc -l)
                local daily_success=0
                if [ $daily_pings -gt 0 ]; then
                    daily_success=$(awk "BEGIN {printf \"%.1f\", ($daily_pings - $daily_timeouts) * 100 / $daily_pings}")
                fi
                
                echo "  Connection: $daily_pings pings, ${daily_success}% success, $daily_timeouts failures"
            else
                echo "  Connection: No data"
            fi
        done
        
        echo ""
        echo "=== PROBLEM ANALYSIS ==="
        
        # Find worst performing days
        echo ""
        echo "WORST SPEED DAYS:"
        for date in $dates_with_data; do
            local date_formatted="${date//-/}"
            local speed_files=$(find "$LOG_DIR" -name "speed_$date_formatted*.log" 2>/dev/null)
            if [ -n "$speed_files" ]; then
                local daily_avg=$(grep "Download:" $speed_files 2>/dev/null | awk '{sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
                echo "$date $daily_avg"
            fi
        done | sort -k2 -n | head -5 | while read date speed; do
            echo "  $date: ${speed} Mb/s average"
        done
        
        echo ""
        echo "CONNECTION PROBLEM DAYS:"
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
            echo "  $date: ${rate}% failure rate ($failures failures)"
        done
        
        # Recent issues
        if [ -f "$LOG_DIR/monitor.log" ]; then
            echo ""
            echo "RECENT ERRORS/PROBLEMS:"
            tail -100 "$LOG_DIR/monitor.log" | grep -i "error\|fail\|błąd\|problem" | tail -10 | while read line; do
                echo "  $line"
            done
        fi
        
        echo ""
        echo "=== COMPLIANCE ASSESSMENT ==="
        echo "According to Play Terms of Service §6 ust. 23:"
        echo ""
        
        if [ -n "$all_speed_files" ] && [ $total_speed_tests -gt 0 ]; then
            local compliance_rate=$(awk "BEGIN {printf \"%.1f\", ($total_speed_tests - $slow_tests) * 100 / $total_speed_tests}")
            echo "Speed Compliance: ${compliance_rate}% of tests meet guaranteed minimum"
            if [ $slow_tests -eq 0 ]; then
                echo "✓ COMPLIANT: All speed tests above 400 Mb/s"
            else
                echo "⚠ POTENTIAL ISSUE: $slow_tests tests below guaranteed minimum"
            fi
        fi
        
        if [ -n "$all_ping_files" ] && [ $total_pings -gt 0 ]; then
            echo "Connection Stability: ${success_rate}% uptime"
            if [ $timeouts -eq 0 ]; then
                echo "✓ EXCELLENT: No connection failures detected"
            elif [ $(echo "$success_rate > 99" | bc -l) -eq 1 ]; then
                echo "✓ GOOD: Minimal connection issues"
            else
                echo "⚠ ISSUES: Connection stability may be below expectations"
            fi
        fi
        
        echo ""
        echo "=== RECOMMENDATIONS ==="
        
        if [ $slow_tests -gt 0 ]; then
            echo "• Contact Play support about speed issues (refer to this report)"
            echo "• Request technical inspection under service guarantee terms"
        fi
        
        if [ $timeouts -gt 0 ]; then
            echo "• Document connection stability issues with timestamps"
            echo "• Check for local network problems first"
        fi
        
        if [ $total_speed_tests -eq 0 ] && [ $total_pings -eq 0 ]; then
            echo "• No monitoring data found - ensure monitoring script is running"
            echo "• Check log directory: $LOG_DIR"
        fi
        
        echo ""
        echo "Report generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Data period: $summary_type"
        echo "Total monitoring sessions analyzed: $(echo $dates_with_data | wc -w) days"
        
    } > "$output_file"
    
    echo ""
    echo "Comprehensive summary generated: $output_file"
    echo ""
    echo "=== SUMMARY PREVIEW ==="
    head -50 "$output_file"
    echo ""
    echo "... (full report saved to file)"
    echo ""
    echo "To view complete report: cat \"$output_file\""
}

# Function to generate summary for a specific date
generate_single_date_summary() {
    local target_date="$1"
    local date_formatted="${target_date//-/}"  # Convert YYYY-MM-DD to YYYYMMDD
    local summary_file="$LOG_DIR/summary_$date_formatted.txt"
    
    echo "Generating summary for $target_date..."
    
    # Check if logs directory exists
    if [ ! -d "$LOG_DIR" ]; then
        echo "ERROR: Logs directory $LOG_DIR not found!"
        echo "Make sure the monitoring script has been running."
        exit 1
    fi
    
    {
        echo "=== PODSUMOWANIE DNIA $date_formatted ==="
        echo "Data: $target_date"
        echo "Wygenerowano: $(date)"
        echo "System: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'=' -f2 | tr -d '"' || uname -s)"
        echo ""
        
        # Find speed test files for this date
        local speed_files=$(find "$LOG_DIR" -name "speed_$date_formatted*.log" 2>/dev/null)
        
        echo "=== TESTY PRĘDKOŚCI ==="
        if [ -n "$speed_files" ] && [ -f $(echo $speed_files | cut -d' ' -f1) ]; then
            # Count total tests
            local total_tests=$(grep "Download:" $speed_files 2>/dev/null | wc -l)
            
            if [ $total_tests -gt 0 ]; then
                # Count slow tests (below 400 Mb/s)
                local slow_tests=$(grep "Download:" $speed_files 2>/dev/null | awk '$2 < 400' | wc -l)
                
                # Calculate average speed
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
        
        # Find ping test files for this date
        local ping_files=$(find "$LOG_DIR" -name "ping_$date_formatted*.log" 2>/dev/null)
        
        echo "=== STABILNOŚĆ POŁĄCZENIA ==="
        if [ -n "$ping_files" ] && [ -f $(echo $ping_files | cut -d' ' -f1) ]; then
            # Count timeouts and successful pings
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
    
    echo "Summary generated: $summary_file"
    echo ""
    echo "=== PODGLĄD PODSUMOWANIA ==="
    cat "$summary_file"
}

# Main script logic
main() {
    local option="$1"
    
    # Check if logs directory exists
    if [ ! -d "$LOG_DIR" ]; then
        echo "ERROR: Logs directory $LOG_DIR not found!"
        echo "Make sure the monitoring script has been running."
        exit 1
    fi
    
    case "$option" in
        "all")
            local all_dates=$(get_available_dates)
            if [ -z "$all_dates" ]; then
                echo "No log files found in $LOG_DIR"
                exit 1
            fi
            generate_comprehensive_summary "$all_dates" "ALL AVAILABLE DATA"
            ;;
        "last7")
            local recent_dates=$(get_dates_in_range 6)  # 0-6 = 7 days
            generate_comprehensive_summary "$recent_dates" "LAST 7 DAYS"
            ;;
        "last30")
            local recent_dates=$(get_dates_in_range 29)  # 0-29 = 30 days
            generate_comprehensive_summary "$recent_dates" "LAST 30 DAYS"
            ;;
        "")
            # No argument - use yesterday
            local yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -d "-1 day" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
            echo "No option provided, generating summary for yesterday: $yesterday"
            generate_single_date_summary "$yesterday"
            ;;
        *)
            # Check if it's a date format
            if date -d "$option" >/dev/null 2>&1; then
                generate_single_date_summary "$option"
            else
                echo "ERROR: Invalid option '$option'"
                echo "Valid options: all, last7, last30, or YYYY-MM-DD date"
                exit 1
            fi
            ;;
    esac
}

# Show usage if --help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Play Internet Comprehensive Summary Generator"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  all              Generate comprehensive summary for ALL available logs"
    echo "  last7            Generate summary for last 7 days"
    echo "  last30           Generate summary for last 30 days"
    echo "  YYYY-MM-DD       Generate summary for specific date"
    echo "  (no args)        Generate summary for yesterday"
    echo ""
    echo "Examples:"
    echo "  $0 all                    # Analyze all available data"
    echo "  $0 last7                  # Last 7 days summary"
    echo "  $0 last30                 # Last 30 days summary"
    echo "  $0 2025-01-25            # Specific date"
    echo "  $0                       # Yesterday only"
    echo ""
    echo "Available dates with logs:"
    get_available_dates | head -10
    echo ""
    exit 0
fi

# Run main function
main "$1"
