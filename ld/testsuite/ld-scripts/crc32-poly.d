#source: crc32-poly.s
#ld: -T crc32-poly.t
#objdump: -s -j .text
#target: [is_elf_format] [is_coff_format]
#notarget: [is_aout_format]
#xfail: tic4x-*-* tic54x-*-*
#skip: ns32k-pc532-macho, pdp11-dec-aout, powerpc-ibm-aix5.2.0
#skip: rs6000-aix4.3.3, alpha-linuxecoff

.*:     file format .*

Contents of section .text:
 1200 434f4445 deadbeef 00000000 00000000  CODE............
 1210 cbf43926 00000000 00000000 00000000  ..9&............
 1220 cbf43926 00000000 00000000 00000000  ..9&............
 1230 00000000 00000000 deadbeef 434f4445  ............CODE
 1240 31323334 35363738 3900ffff ffffffff  123456789.......
 1250 434f4445 00000000 00000000 00000000  CODE............
 1260 ffffffff ffffffff ffffffff ffffffff  .*
#...
 17e0 434f4445 deadbeef 00000000 00000000  CODE............
 17f0 44494745 53542054 41424c45 00000000  DIGEST TABLE....
#...
 1c00 454e4420 5441424c 45000000 00000000  END TABLE.......
 1c10 00000000 00000000 deadbeef 434f4445  ............CODE
#pass
