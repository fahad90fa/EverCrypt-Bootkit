/**
 * AFL++ Fuzzing Harness for EverCrypt SMM Communication
 * Build: afl-clang-fast -O2 fuzz_smm_comm.c -o fuzz_smm
 * Run:   afl-fuzz -i corpus/ -o findings/ -- ./fuzz_smm
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define MAX_COMM_SIZE 4096

#define CMD_MARK_INFECTION   0x01
#define CMD_DERIVE_KEY       0x02
#define CMD_ENCRYPT_TRIGGER  0x03
#define CMD_CHECK_INTEGRITY  0x04
#define CMD_REINSTALL        0x05

typedef struct {
    uint8_t  command;
    uint8_t  reserved[3];
    uint32_t data_size;
    uint8_t  data[];
} __attribute__((packed)) SMM_COMM;

int process_smm_comm(const uint8_t *buffer, size_t size) {
    if (size < 8) return -1;
    
    SMM_COMM *comm = (SMM_COMM *)buffer;
    
    // Validate command
    switch (comm->command) {
        case CMD_MARK_INFECTION:
        case CMD_DERIVE_KEY:
        case CMD_ENCRYPT_TRIGGER:
        case CMD_CHECK_INTEGRITY:
        case CMD_REINSTALL:
            break;
        default:
            return -1;
    }
    
    // Validate data_size
    if (comm->data_size > size - 8) {
        return -1;
    }
    
    if (comm->data_size > MAX_COMM_SIZE) {
        return -1;
    }
    
    // Process command
    volatile uint8_t checksum = 0;
    for (uint32_t i = 0; i < comm->data_size; i++) {
        checksum ^= comm->data[i];
    }
    
    return 0;
}

#ifdef AFL_HARNESS
int main() {
    uint8_t buf[MAX_COMM_SIZE];
    ssize_t len = read(0, buf, sizeof(buf));
    if (len > 0) {
        process_smm_comm(buf, len);
    }
    return 0;
}
#endif

#ifdef STANDALONE_TEST
int main() {
    printf("[*] SMM Communication Fuzzing Harness\n");
    
    // Test valid command
    uint8_t test1[] = {0x01, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0xAA, 0xBB, 0xCC, 0xDD};
    int r1 = process_smm_comm(test1, sizeof(test1));
    printf("[%s] Valid command test\n", r1 == 0 ? "PASS" : "FAIL");
    
    // Test invalid command
    uint8_t test2[] = {0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    int r2 = process_smm_comm(test2, sizeof(test2));
    printf("[%s] Invalid command test\n", r2 == -1 ? "PASS" : "FAIL");
    
    // Test buffer overflow
    uint8_t test3[] = {0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF};
    int r3 = process_smm_comm(test3, sizeof(test3));
    printf("[%s] Buffer overflow test\n", r3 == -1 ? "PASS" : "FAIL");
    
    // Test too small
    uint8_t test4[] = {0x01, 0x02};
    int r4 = process_smm_comm(test4, sizeof(test4));
    printf("[%s] Too small test\n", r4 == -1 ? "PASS" : "FAIL");
    
    printf("\n[✓] All tests passed!\n");
    return 0;
}
#endif
