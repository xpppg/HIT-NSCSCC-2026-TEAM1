#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
    FILE *in;
    FILE *out;
    unsigned char mem[32];

    FILE *in_data;
    out = fopen("rom.vlog", "w");
    if (!out) { perror("rom.vlog"); return 1; }

    // =============================================
    // 1. U-Boot 二进制 → 加载到物理地址 0x300000
    //    (通过 DMW1 映射, 虚拟地址 = 0xa0300000)
    // =============================================
    in = fopen("uboot_raw.bin", "rb");
    if (!in) { perror("uboot_raw.bin"); return 1; }
    fprintf(out, "@300000\n");
    int byte_count = 0;
    while (!feof(in)) {
        if (fread(mem, 1, 1, in) != 1) break;
        fprintf(out, "%02x\n", mem[0]);
        byte_count++;
    }
    fclose(in);
    printf("U-Boot: %d bytes loaded at 0x300000\n", byte_count);

    // =============================================
    // 2. init_5f.txt → 0x5f00000 (如果需要)
    // =============================================
    FILE *in_init_5f = fopen("init_5f.txt", "r");
    if (in_init_5f) {
        fprintf(out, "@5f00000\n");
        while (!feof(in_init_5f)) {
            if (fread(mem, 3, 1, in_init_5f) != 1) break;
            fprintf(out, "%c%c%c", mem[0], mem[1], mem[2]);
        }
        fclose(in_init_5f);
    }

    // =============================================
    // 3. start.bin → 0x1c000000 (CPU 复位入口)
    // =============================================
    in_data = fopen("start.bin", "rb");
    if (!in_data) { perror("start.bin"); return 1; }
    fprintf(out, "@1c000000\n");
    while (!feof(in_data)) {
        if (fread(mem, 1, 1, in_data) != 1) break;
        fprintf(out, "%02x\n", mem[0]);
    }
    fclose(in_data);

    fclose(out);
    printf("rom.vlog generated successfully.\n");
    return 0;
}
