#include "minilang.h"

char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "Cannot open file: %s\n", path); exit(1); }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(size + 1);
    fread(buf, 1, size, f);
    buf[size] = '\0';
    fclose(f);
    return buf;
}

void die(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
    exit(1);
}

static void usage(const char *prog) {
    fprintf(stderr, "Usage: %s <command> <file>\n", prog);
    fprintf(stderr, "Commands:\n");
    fprintf(stderr, "  run       Compile to bytecode and run in VM\n");
    fprintf(stderr, "  bytecode  Compile and dump bytecode (human readable)\n");
    fprintf(stderr, "  dump-text Compile and dump bytecode (text format, for self-hosting compare)\n");
    fprintf(stderr, "  llvm      Compile to LLVM IR (.ll)\n");
    fprintf(stderr, "  build     Compile to native executable (LLVM IR + link)\n");
    exit(1);
}

static void dump_bytecode_text(Program *prog) {
    printf("MINILANGBC\n");
    printf("%d\n", prog->const_count);
    for (int i = 0; i < prog->const_count; i++) {
        Value *c = &prog->constants[i];
        if (c->type == VAL_INT) {
            printf("0 %lld\n", (long long)c->as.integer);
        } else if (c->type == VAL_STRING) {
            printf("1 %s\n", c->as.string);
        } else {
            printf("0 0\n");
        }
    }
    printf("%d\n", prog->func_count);
    for (int i = 0; i < prog->func_count; i++) {
        FuncInfo *f = &prog->funcs[i];
        printf("%s %d %d %d\n", f->name, f->address, f->param_count, f->local_count);
    }
    int num_instr = prog->bc.count / 3;
    printf("%d\n", num_instr);
    for (int i = 0; i < num_instr; i++) {
        printf("%d %d %d\n", prog->bc.code[i*3], prog->bc.code[i*3+1], prog->bc.code[i*3+2]);
    }
}

static void dump_bytecode(Program *prog) {
    printf("=== Constants (%d) ===\n", prog->const_count);
    for (int i = 0; i < prog->const_count; i++) {
        printf("  [%d] ", i);
        value_print(prog->constants[i], 1);
    }
    printf("=== Functions (%d) ===\n", prog->func_count);
    for (int i = 0; i < prog->func_count; i++) {
        FuncInfo *f = &prog->funcs[i];
        printf("  [%d] %s addr=%d params=%d locals=%d\n", i, f->name, f->address, f->param_count, f->local_count);
    }
    printf("=== Bytecode (%d instructions) ===\n", prog->bc.count / 3);
    for (int i = 0; i < prog->bc.count; i += 3) {
        int op = prog->bc.code[i];
        int op1 = prog->bc.code[i+1];
        int op2 = prog->bc.code[i+2];
        const char *name = "???";
        switch (op) {
            case OP_CONST: name="CONST"; break;
            case OP_NIL: name="NIL"; break;
            case OP_ADD: name="ADD"; break;
            case OP_SUB: name="SUB"; break;
            case OP_MUL: name="MUL"; break;
            case OP_DIV: name="DIV"; break;
            case OP_MOD: name="MOD"; break;
            case OP_NEG: name="NEG"; break;
            case OP_EQ: name="EQ"; break;
            case OP_NEQ: name="NEQ"; break;
            case OP_LT: name="LT"; break;
            case OP_GT: name="GT"; break;
            case OP_LTE: name="LTE"; break;
            case OP_GTE: name="GTE"; break;
            case OP_AND: name="AND"; break;
            case OP_OR: name="OR"; break;
            case OP_NOT: name="NOT"; break;
            case OP_LOAD: name="LOAD"; break;
            case OP_STORE: name="STORE"; break;
            case OP_PRINT: name="PRINT"; break;
            case OP_PRINTLN: name="PRINTLN"; break;
            case OP_JMP: name="JMP"; break;
            case OP_JMPF: name="JMPF"; break;
            case OP_CALL: name="CALL"; break;
            case OP_RET: name="RET"; break;
            case OP_ARRAY: name="ARRAY"; break;
            case OP_INDEX: name="INDEX"; break;
            case OP_INDEX_SET: name="INDEX_SET"; break;
            case OP_POP: name="POP"; break;
            case OP_HALT: name="HALT"; break;
            case OP_CONCAT: name="CONCAT"; break;
            case OP_LEN: name="LEN"; break;
            case OP_CHARAT: name="CHARAT"; break;
            case OP_SUBSTR: name="SUBSTR"; break;
            case OP_TOSTRING: name="TOSTRING"; break;
            case OP_TOINT: name="TOINT"; break;
            case OP_STRCMP: name="STRCMP"; break;
        }
        printf("  %4d: %-12s %6d %6d\n", i/3, name, op1, op2);
    }
}

int main(int argc, char **argv) {
    if (argc < 3) usage(argv[0]);

    const char *cmd = argv[1];
    const char *file = argv[2];

    char *src = read_file(file);
    Lexer *lexer = lexer_new(src);
    lex(lexer);
    Parser *parser = parser_new(lexer);
    parse(parser);

    if (strcmp(cmd, "run") == 0) {
        Program *prog = compile_to_bytecode(parser);
        VM *vm = vm_new(prog);
        Value result = vm_run(vm);
        vm_free(vm);
        program_free(prog);
        (void)result;
    } else if (strcmp(cmd, "bytecode") == 0) {
        Program *prog = compile_to_bytecode(parser);
        dump_bytecode(prog);
        program_free(prog);
    } else if (strcmp(cmd, "dump-text") == 0) {
        Program *prog = compile_to_bytecode(parser);
        dump_bytecode_text(prog);
        program_free(prog);
    } else if (strcmp(cmd, "llvm") == 0) {
        char *ir = generate_llvm_ir(parser);
        // Output to .ll file
        char outpath[1024];
        snprintf(outpath, sizeof(outpath), "%s", file);
        char *dot = strrchr(outpath, '.');
        if (dot) strcpy(dot, ".ll");
        else strcat(outpath, ".ll");
        FILE *f = fopen(outpath, "w");
        if (!f) { fprintf(stderr, "Cannot write %s\n", outpath); exit(1); }
        fputs(ir, f);
        fclose(f);
        printf("LLVM IR written to %s\n", outpath);
        free(ir);
    } else if (strcmp(cmd, "build") == 0) {
        char *ir = generate_llvm_ir(parser);
        char base[1024];
        snprintf(base, sizeof(base), "%s", file);
        char *dot = strrchr(base, '.');
        if (dot) *dot = '\0';

        char llpath[1024], opath[1024], binpath[1024];
        snprintf(llpath, sizeof(llpath), "%s.ll", base);
        snprintf(opath, sizeof(opath), "%s.o", base);
        snprintf(binpath, sizeof(binpath), "%s", base);

        FILE *f = fopen(llpath, "w");
        if (!f) { fprintf(stderr, "Cannot write %s\n", llpath); exit(1); }
        fputs(ir, f);
        fclose(f);
        free(ir);

        // Compile IR to object using ir_compile.py
        char cmd_buf[2048];
        snprintf(cmd_buf, sizeof(cmd_buf),
                 "python3 %s/ir_compile.py %s %s",
                 getenv("MINILANG_DIR") ? getenv("MINILANG_DIR") : ".",
                 llpath, opath);
        int ret = system(cmd_buf);
        if (ret != 0) { fprintf(stderr, "IR compilation failed\n"); exit(1); }

        // Link with runtime
        snprintf(cmd_buf, sizeof(cmd_buf),
                 "gcc -o %s %s %s/runtime.c -O2 2>&1",
                 binpath, opath, getenv("MINILANG_DIR") ? getenv("MINILANG_DIR") : ".");
        ret = system(cmd_buf);
        if (ret != 0) { fprintf(stderr, "Link failed\n"); exit(1); }

        printf("Executable built: %s\n", binpath);
    } else {
        usage(argv[0]);
    }

    parser_free(parser);
    lexer_free(lexer);
    free(src);
    return 0;
}
