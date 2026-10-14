/* Windows x64 call bridge. All arguments are numeric; no core patching.
 * ULONG inputs retain intentionally nonzero upper bits around BOOLEAN low byte.
 * args: target, handle, buffer, size, single_raw, restart_raw, context, ret_size
 */
.text
.globl call_raw_query
.def call_raw_query; .scl 2; .type 32; .endef
.seh_proc call_raw_query
call_raw_query:
    subq $72, %rsp
    .seh_stackalloc 72
    .seh_endprologue
    movq %rcx, %r11
    movq %rdx, %rcx
    movq %r8, %rdx
    movl %r9d, %r8d
    movl 112(%rsp), %r9d
    movl 120(%rsp), %eax
    movq %rax, 32(%rsp)
    movq 128(%rsp), %rax
    movq %rax, 40(%rsp)
    movq 136(%rsp), %rax
    movq %rax, 48(%rsp)
    call *%r11
    addq $72, %rsp
    ret
.seh_endproc
