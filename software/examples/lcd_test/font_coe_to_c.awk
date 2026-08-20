# Convert the 1-bit Vivado font ROM into packed 16x32 C glyphs.
# Input order is {ascii[6:0], pixel[8:0]}: 32 rows of 16 pixels per glyph.

BEGIN {
    in_vector = 0
    pixel_count = 0
    glyph_count = 0
    row_in_glyph = 0
    row_value = 0

    print "/* Generated from IP/LCD/font_rom.coe. Do not edit by hand. */"
    print "#ifndef LCD_FONT_16X32_H"
    print "#define LCD_FONT_16X32_H"
    print ""
    print "#include <stdint.h>"
    print ""
    print "#define LCD_FONT_WIDTH  16U"
    print "#define LCD_FONT_HEIGHT 32U"
    print "#define LCD_FONT_GLYPHS 128U"
    print ""
    print "static const uint16_t lcd_font_16x32[LCD_FONT_GLYPHS][LCD_FONT_HEIGHT] = {"
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

    if (value != "0" && value != "1") {
        print "Invalid font bit: " $0 > "/dev/stderr"
        failed = 1
        next
    }

    row_value = row_value * 2 + value
    ++pixel_count

    if ((pixel_count % 16) == 0) {
        if (row_in_glyph == 0)
            printf "    { /* ASCII %u */\n        ", glyph_count

        printf "0x%04xU", row_value
        ++row_in_glyph
        row_value = 0

        if (row_in_glyph == 32) {
            print "\n    },"
            row_in_glyph = 0
            ++glyph_count
        } else if ((row_in_glyph % 8) == 0) {
            printf ",\n        "
        } else {
            printf ", "
        }
    }
}

END {
    print "};"
    print ""
    print "#endif"

    if (!in_vector || pixel_count != 65536 || glyph_count != 128 ||
        row_in_glyph != 0) {
        print "Expected 128 glyphs/65536 bits, got " glyph_count \
              " glyphs/" pixel_count " bits" > "/dev/stderr"
        exit 1
    }
    if (failed)
        exit 1
}
