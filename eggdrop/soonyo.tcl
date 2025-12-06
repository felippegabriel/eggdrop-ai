######################################################################
# soonyo.tcl - LLM-powered IRC bot via local gateway
#
# Installation:
#   1. Copy this file to your eggdrop/scripts/ directory
#   2. Add "source scripts/soonyo.tcl" to your eggdrop.conf
#   3. .rehash or restart the bot
#
# Requirements:
#   - Eggdrop with http package (standard in modern Eggdrop)
#   - Local gateway running on http://127.0.0.1:3042
######################################################################

package require http

# Configuration
set soonyo_gateway "http://127.0.0.1:3042/soonyo"
set soonyo_timeout 15000
set soonyo_rate_limit 10 ;# seconds between requests per user

# Rate limiting storage: array of user -> timestamp
array set soonyo_last_request {}

# Bind to public channel messages
bind pub - * soonyo_pub_handler

proc soonyo_pub_handler {nick uhost hand chan text} {
    global soonyo_last_request soonyo_rate_limit
    
    # Check if message mentions the bot
    set trigger ""
    if {[regexp -nocase {^@soonyo[:\s]+(.+)} $text match query]} {
        set trigger "@soonyo"
    } elseif {[regexp -nocase {^soonyo[:\s]+(.+)} $text match query]} {
        set trigger "soonyo:"
    } else {
        return 0
    }
    
    # Rate limiting check
    set now [clock seconds]
    set user_key "${nick}!${chan}"
    
    if {[info exists soonyo_last_request($user_key)]} {
        set elapsed [expr {$now - $soonyo_last_request($user_key)}]
        if {$elapsed < $soonyo_rate_limit} {
            set wait [expr {$soonyo_rate_limit - $elapsed}]
            putserv "PRIVMSG $chan :$nick: please wait ${wait}s"
            return 0
        }
    }
    
    # Update rate limit timestamp
    set soonyo_last_request($user_key) $now
    
    # Clean up the query
    set query [string trim $query]
    
    if {$query eq ""} {
        putserv "PRIVMSG $chan :$nick: yes?"
        return 0
    }
    
    # Send request to gateway
    soonyo_query $nick $chan $query
    
    return 0
}

proc soonyo_query {nick chan message} {
    global soonyo_gateway soonyo_timeout
    
    # Build JSON payload
    set json_message [soonyo_json_escape $message]
    set json_user [soonyo_json_escape $nick]
    set json_channel [soonyo_json_escape $chan]
    
    set payload "\{\"message\":\"$json_message\",\"user\":\"$json_user\",\"channel\":\"$json_channel\"\}"
    
    # Make HTTP POST request
    if {[catch {
        set token [::http::geturl $soonyo_gateway \
            -query $payload \
            -timeout $soonyo_timeout \
            -type "application/json" \
            -headers [list "Content-Type" "application/json"]]
        
        set status [::http::status $token]
        set ncode [::http::ncode $token]
        set data [::http::data $token]
        
        ::http::cleanup $token
        
        if {$status eq "ok" && $ncode == 200} {
            # Split response into lines if needed (for long responses)
            set lines [split $data "\n"]
            foreach line $lines {
                set line [string trim $line]
                if {$line ne ""} {
                    putserv "PRIVMSG $chan :$line"
                }
            }
        } else {
            putserv "PRIVMSG $chan :$nick: gateway error (status: $status, code: $ncode)"
        }
    } error]} {
        putserv "PRIVMSG $chan :$nick: failed to reach gateway - $error"
    }
}

proc soonyo_json_escape {text} {
    # Escape special JSON characters
    set text [string map {
        "\\" "\\\\"
        "\"" "\\\""
        "\n" "\\n"
        "\r" "\\r"
        "\t" "\\t"
    } $text]
    return $text
}

# Cleanup old rate limit entries (every 5 minutes)
bind time - "*/5 * * * *" soonyo_cleanup

proc soonyo_cleanup {min hour day month year} {
    global soonyo_last_request soonyo_rate_limit
    
    set now [clock seconds]
    set cutoff [expr {$now - ($soonyo_rate_limit * 10)}]
    
    foreach key [array names soonyo_last_request] {
        if {$soonyo_last_request($key) < $cutoff} {
            unset soonyo_last_request($key)
        }
    }
}

putlog "soonyo.tcl loaded - LLM gateway ready"
