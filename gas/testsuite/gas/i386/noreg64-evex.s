# Check 64-bit insns not sizeable through register operands with evex

        .text
_start:
	{evex} adc	$1, (%rax)
	{evex} adc	$0x89, (%rax)
	{evex} adc	$0x1234, (%rax)
	{evex} adc	$0x12345678, (%rax)
	{evex} add	$1, (%rax)
	{evex} add	$0x89, (%rax)
	{evex} add	$0x1234, (%rax)
	{evex} add	$0x12345678, (%rax)
	{evex} and	$1, (%rax)
	{evex} and	$0x89, (%rax)
	{evex} and	$0x1234, (%rax)
	{evex} and	$0x12345678, (%rax)
	{evex} crc32	(%rax), %eax
	{evex} crc32	(%rax), %rax
	{evex} dec	(%rax)
	{evex} div	(%rax)
	{evex} idiv	(%rax)
	{evex} imul	(%rax)
	{evex} inc	(%rax)
	{evex} mul	(%rax)
	{evex} neg	(%rax)
	{evex} not	(%rax)
	{evex} or 	$1, (%rax)
	{evex} or 	$0x89, (%rax)
	{evex} or 	$0x1234, (%rax)
	{evex} or 	$0x12345678, (%rax)
	{evex} rcl	$1, (%rax)
	{evex} rcl	$2, (%rax)
	{evex} rcl	%cl, (%rax)
	{evex} rcr	$1, (%rax)
	{evex} rcr	$2, (%rax)
	{evex} rcr	%cl, (%rax)
	{evex} rol	$1, (%rax)
	{evex} rol	$2, (%rax)
	{evex} rol	%cl, (%rax)
	{evex} ror	$1, (%rax)
	{evex} ror	$2, (%rax)
	{evex} ror	%cl, (%rax)
	{evex} sal	$1, (%rax)
	{evex} sal	$2, (%rax)
	{evex} sal	%cl, (%rax)
	{evex} sar	$1, (%rax)
	{evex} sar	$2, (%rax)
	{evex} sar	%cl, (%rax)
	{evex} sbb	$1, (%rax)
	{evex} sbb	$0x89, (%rax)
	{evex} sbb	$0x1234, (%rax)
	{evex} sbb	$0x12345678, (%rax)
	{evex} shl	$1, (%rax)
	{evex} shl	$2, (%rax)
	{evex} shl	%cl, (%rax)
	{evex} shr	$1, (%rax)
	{evex} shr	$2, (%rax)
	{evex} shr	%cl, (%rax)
	{evex} sub	$1, (%rax)
	{evex} sub	$0x89, (%rax)
	{evex} sub	$0x1234, (%rax)
	{evex} sub	$0x12345678, (%rax)
	{evex} xor	$1, (%rax)
	{evex} xor	$0x89, (%rax)
	{evex} xor	$0x1234, (%rax)
	{evex} xor	$0x12345678, (%rax)
