/* sysreg-2.s Test file for ARMv8.2 system registers.  */

	.include "sysreg-test-utils.inc"

	.text

	rw_sys_reg sys_reg=id_aa64mmfr1_el1 w=0
	rw_sys_reg sys_reg=id_aa64mmfr2_el1 w=0
	rw_sys_reg sys_reg=id_aa64mmfr3_el1 w=0
	rw_sys_reg sys_reg=id_aa64mmfr4_el1 w=0

	/* RAS extension.  */

	rw_sys_reg sys_reg=erridr_el1 w=0
	rw_sys_reg sys_reg=errselr_el1

	rw_sys_reg sys_reg=erxfr_el1 w=0
	rw_sys_reg sys_reg=erxctlr_el1
	rw_sys_reg sys_reg=erxstatus_el1
	rw_sys_reg sys_reg=erxaddr_el1

	rw_sys_reg sys_reg=erxmisc0_el1
	rw_sys_reg sys_reg=erxmisc1_el1

	rw_sys_reg sys_reg=vsesr_el2 w=0
	rw_sys_reg sys_reg=disr_el1
	rw_sys_reg sys_reg=vdisr_el2 w=0

	/* DC CVAP.  */

	dc cvac, x0
	dc cvau, x1
	dc cvap, x2

	/* AT.  */

	at s1e1rp, x0
	at s1e1wp, x1

	/* Statistical profiling.  */

	.irp reg, pmblimitr_el1, pmbptr_el1, pmbsr_el1
	rw_sys_reg sys_reg=\reg
	.endr

	.irp reg, pmscr_el1, pmsicr_el1, pmsirr_el1, pmsfcr_el1
	rw_sys_reg sys_reg=\reg
	.endr

	.irp reg, pmsevfr_el1, pmslatfr_el1, pmscr_el2, pmscr_el12
	rw_sys_reg sys_reg=\reg
	.endr

	.irp reg, pmbidr_el1, pmsidr_el1
	rw_sys_reg sys_reg=\reg w=0
	.endr
