# Convert the Vivado LCD reset ROM into a C table.
#
# rst_rom.coe word format (matching the original LCD RTL):
#   bit 16     1 = command, 0 = data
#   bits 15:0 value driven on lcd_db

BEGIN {
    in_vector = 0
    count = 0

    print "/* Generated from IP/LCD/rst_rom.coe. Do not edit by hand. */"
    print "#ifndef LCD_INIT_SEQUENCE_H"
    print "#define LCD_INIT_SEQUENCE_H"
    print ""
    print "#include <stdint.h>"
    print ""
    print "#define LCD_INIT_COMMAND_FLAG 0x00010000U"
    print "#define LCD_INIT_PRE_SLEEP_COUNT 763U"
    print ""
    print "static const uint32_t lcd_init_sequence[] = {"
}

/^[[:space:]]*memory_initialization_vector[[:space:]]*=/ {
    in_vector = 1
    next
}

in_vector {
    value = $0
    gsub(/[[:space:],;]/, "", value)
    if (value == "")
        next

    if (value !~ /^[[:xdigit:]]+$/) {
        print "Invalid COE value: " $0 > "/dev/stderr"
        failed = 1
        next
    }

    printf "    0x%sU,\n", tolower(value)
    ++count
}

END {
    print "};"
    print ""
    print "#define LCD_INIT_SEQUENCE_COUNT ((uint32_t)(sizeof(lcd_init_sequence) / sizeof(lcd_init_sequence[0])))"
    print ""
    print "#endif"

    if (!in_vector || count != 783) {
        print "Expected 783 LCD initialization words, got " count > "/dev/stderr"
        exit 1
    }
    if (failed)
        exit 1
}
