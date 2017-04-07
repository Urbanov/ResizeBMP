############################## DEFINES ##############################
	# destination pixel position [x, y]
	.eqv destX $s0
	.eqv destY $s1

	# source pixel position [i, j]
	.eqv srcI $s2
	.eqv srcJ $s3
	
	# difference between real source pixels and projected destination pixels
	.eqv devX1 $t7
	.eqv devY1 $t6
	.eqv devX2 $t5
	.eqv devY2 $t4
	
	# actual weights taken into calculations
	# if srcI is first pixel, dx = devX1
	# if srcI is last pixel, dx = 1 - devX2
	# else dx = 1 (full pixel)
	.eqv dx $s4
	.eqv dy $s5

	# RGB values for new image
	.eqv destR $s6
	.eqv destG $s7
	.eqv destB $a3
	

############################## DATA SEGMENT ##############################
	.data
input_msg:	.asciiz "input file path: "
output_msg:	.asciiz "output file path: "
error_msg:	.asciiz "cannot open file\n"
working_msg:	.asciiz "working...\n"
done_msg:	.asciiz "done!\noutput file path: "

input_name:	.space 100	# input path
output_name:	.space 100	# output path
input_header:	.space 54
output_header:	.space 54
input_arr:	.word 0		# address of pixel array of src img
row_size:	.word 0		# src img row size in bytes
padding_size:	.word 0		# dest img padding
dest_height:	.word 0
dest_width:	.word 0
src_height:	.word 0
src_width:	.word 0
scaleX:		.word 0		# src_width / dest_width
scaleY:		.word 0		# src_height / dest_height
inverseX:	.word 0		# 1 / scaleX
inverseY:	.word 0		# 1 / scaleY
inverseXY:	.word 0		# 1 / (scaleX * scaleY)
istart:		.word 0
iend:		.word 0
jstart:		.word 0
jend:		.word 0
color_buf:	.word 0		# used for writing RGB values into destination image
null_bytes:	.word 0		# used for padding
	
	
	.text
############################## MACROS ##############################
	# prints string from %addr
	.macro printStr (%addr)
	li $v0, 4
	la $a0, %addr
	syscall
	.end_macro
	
	# reads string not longer than %n bytes into %addr 
	.macro readStr (%addr, %n)
	la $a0, %addr
	li $a1, %n
	li $v0, 8
	syscall
	.end_macro
	
	# removes \n from string
	.macro removeNewline (%addr)
	la $t8, %addr
loop:
	lb $t9, ($t8)
	beq $t9, '\n', remove
	addiu $t8, $t8, 1
	b loop
remove:
	sb $zero, ($t8)
	.end_macro

	# changes 32 bit integer into fixed point number with 16 bit integer and 16 bit fraction
	.macro fixed (%dest, %int)
	sll %dest, %int, 16
	.end_macro
	
	# 32 bit integer from fixed point
	.macro int (%dest, %fixed)
	srl %dest, %fixed, 16
	.end_macro
	
	# removes fraction part from fixed point number
	.macro trunc (%dest, %fixed)
	int (%dest, %fixed)
	fixed (%dest, %dest)
	.end_macro
	
	# 32 bit integer from fixed point, but rounded
	.macro round (%dest, %fixed)
	srl $t8, %fixed, 15
	andi $t8, $t8, 1
	int ($t9, %fixed)
	addu %dest, $t9, $t8
	.end_macro

	# mult for fixed point numbers
	.macro fixedMult (%dest, %arg1, %arg2)
	multu %arg1, %arg2
	mfhi %dest
	sll %dest, %dest, 16
	mflo $t8
	srl $t8, $t8, 16
	or %dest, %dest, $t8
	.end_macro

	# div for fixed point numbers
	.macro fixedDiv (%dest, %arg1, %arg2)
	sll $t8, %arg1, 4
	srl $t9, %arg2, 12
	divu $t8, $t9
	mflo %dest
	.end_macro
	
	# gets address of pixel at [i, j] coords
	# i * rowsize + 24 * j + input_arr
	.macro getPixel (%dest, %i, %j)
	lw $t8, row_size
	multu $t8, %i
	mflo %dest
	li $t8, 3
	multu $t8, %j
	mflo $t8
	addu %dest, %dest, $t8
	lw $t8, input_arr
	addu %dest, %dest, $t8
	.end_macro

############################## MAIN PROGRAM ##############################
	.globl main
main:
	# get paths
	printStr (input_msg)
	readStr (input_name, 99)
	removeNewline (input_name)
	printStr (output_msg)
	readStr (output_name, 99)
	removeNewline (output_name)

	# open input file for reading
	la $a0, input_name
	li $a1, 0
	li $v0, 13
	syscall
	bltz $v0, error_opening
	move $s0, $v0
	
	# open output file for reading
	la $a0, output_name
	li $a1, 0
	li $v0, 13
	syscall
	bltz $v0, error_opening
	move $s1, $v0
	
	# everything fine so far
	printStr (working_msg)

	# load input file header (first 54 bytes of bmp)
	li $v0, 14
	move $a0, $s0
	la $a1, input_header
	li $a2, 54
	syscall
	
	# load output file header
	li $v0, 14
	move $a0, $s1
	la $a1, output_header
	li $a2, 54
	syscall
	
	# close output file
	li $v0, 16
	move $a0, $s1
	syscall
	
	# store input width and height
	ulw $t0, input_header+18
	ulw $t1, input_header+22
	sw $t0, src_width
	sw $t1, src_height
   
	# store output width and height
	ulw $t2, output_header+18
	ulw $t3, output_header+22
	sw $t2, dest_width
	sw $t3, dest_height
	
	# calculate X and Y scale
	fixed ($t0, $t0)
	fixed ($t1, $t1)
	fixed ($t2, $t2)
	fixed ($t3, $t3)
	fixedDiv ($t0, $t0, $t2)
	sw $t0, scaleX
	fixedDiv ($t1, $t1, $t3)
	sw $t1, scaleY

	# calculate some values to speed up other calculations
	li $t2, 1
	fixed ($t2, $t2)
	fixedDiv ($t3, $t2, $t0) # 1 / scaleX
	sw $t3, inverseX
	fixedDiv ($t4, $t2, $t1) # 1 / scaleY
	sw $t4, inverseY
	fixedMult ($t5, $t3, $t4) # 1 / (scaleX * scaleY)
	sw $t5, inverseXY
	
	# calculate input row size in bytes
	# floor(bpp * width + 31 / 32) * 4
	ulw $t1, input_header+18
	sll $t0, $t1, 1
	addu $t0, $t0, $t1
	sll $t0, $t0, 3
	addiu $t0, $t0, 31
	srl $t0, $t0, 5
	sll $t0, $t0, 2
	sw $t0, row_size
	
	# calculate output padding in bytes
	# (4 - ((width * 3) % 4)) % 4
	ulw $t1, output_header+18
	sll $t0, $t1, 1
	addu $t0, $t0, $t1
	andi $t0, $t0, 3
	li $t1, 4
	subu $t0, $t1, $t0
	andi $t0, $t0, 3
	sw $t0, padding_size
	
	# calculate size of pixel array
	# filesize - headersize
	ulw $t0, input_header+2
	subiu $a0, $t0, 54
	
	# allocate heap memory for pixel array
	li $v0, 9
	syscall
	sw $v0, input_arr
	
	# read data from file
	move $a2, $a0
	move $a0, $s0
	lw $a1, input_arr
	li $v0, 14
	syscall
	
	# close input file
	li $v0, 16
	syscall
	
	# open output file for writing
	la $a0, output_name
	li $a1, 1
	li $v0, 13
	syscall
    
    	# write output header
    	move $a0, $v0
	la $a1, output_header
	li $a2, 54
	li $v0, 15
	syscall	# keep file descriptor in $a0		   

	# iterate over destination rows
	# for (destY = 0; destY < dest_height; ++destY)
	move destY, $zero
for_destY: 
	fixed ($t0, destY)
	lw $t1, scaleY
	
	# project destination row onto source row
	fixedMult ($t0, $t0, $t1) # scaleY * destY
    	addu $t1, $t0, $t1 # scaleY * destY + scaleY
    	
	# get first and last vertical pixel covered by projected destination row
    	int ($t2, $t0) # jstart
    	int ($t3, $t1) # jend
    	
    	# if last vertical pixel (jend) is equal or bigger than source height (due to fixed point 
    	# number approximation), subtract 1 from it
	lw $t8, src_height
	blt $t3, $t8, y_within_bounds
	subiu $t3, $t3, 1
y_within_bounds:
	sw $t2, jstart
	sw $t3, jend

	# devY1 = 1 + jstart - scaleY * destY
	li devY1, 1
	fixed (devY1, devY1)
	fixed ($t2, $t2)
	fixed ($t3, $t3)
	addu devY1, devY1, $t2
	subu devY1, devY1, $t0

	# devY2 = 1 + jend - (scaleY * destY + scaleY)
	li devY2, 1
	fixed (devY2, devY2)
	addu devY2, devY2, $t3
	subu devY2, devY2, $t1
   
  	# iterate over destination columns
	# for (destX = 0; destX < dest_width; ++destX)
    	move destX, $zero
for_destX:
	fixed ($t0, destX)
	lw $t1, scaleX
	
	fixedMult ($t0, $t0, $t1) # scaleX * destX
    	addu $t1, $t0, $t1 # scaleX * destX + scaleX
    
    	# get first and last horizontal pixel covered by projected destination column
    	int ($t2, $t0) # istart
    	int ($t3, $t1) # iend
    	
	# if last horizontal pixel (iend) is equal or bigger than source width (due to fixed point 
	# number approximation), subtract 1 from it
	lw $t8, src_width
	blt $t3, $t8, x_within_bounds
	subiu $t3, $t3, 1
x_within_bounds:
	sw $t2, istart
	sw $t3, iend
   
	#devX1 = 1 + istart - scaleX * destX
	li devX1, 1
	fixed (devX1, devX1)
	fixed ($t2, $t2)
	fixed ($t3, $t3)
	addu devX1, devX1, $t2
	subu devX1, devX1, $t0
	
	# devX2 = 1 + iend - (scaleX * destX + scaleX)
	li devX2, 1
	fixed (devX2, devX2)
	addu devX2, devX2, $t3
	subu devX2, devX2, $t1
	
	# clear destination RGB values
	move destR, $zero
	move destG, $zero
	move destB, $zero
	
	# first row, so dy is devY1
	move dy, devY1
	
	# iterate over source rows
	# for (srcJ = jstart; srcJ <= jend; ++srcJ)
	lw srcJ, jstart
for_srcJ:

	# check whether we arrived at the last row of pixels
	lw $t0, jend
	bne srcJ, $t0, not_last_row
	subu dy, dy, devY2	
not_last_row:

	# first column, so dx is devX1
	move dx, devX1
   
   	# iterate over source columns
	# for (srcI = istart; srcI <= iend; ++srcI)
	lw srcI, istart
for_srcI:

	# check whether we arrived at the last column of pixels
	lw $t0, iend
	bne srcI, $t0, not_last_column
	subu dx, dx, devX2
not_last_column:

	# calculate area (weight)
	# dx * dy / (scaleX * scaleY)
	lw $t0, inverseXY
	fixedMult ($t0, dx, $t0)
	fixedMult ($t0, dy, $t0)

	# get address of pixel [i, j] in source image
	getPixel ($t1, srcJ, srcI)

	lbu $t2, ($t1) # read blue
	fixed ($t2, $t2)
	fixedMult ($t2, $t2, $t0) # blue * weight
	addu destB, destB, $t2 # add blue * weight to accumulator
	
	lbu $t2, 1($t1) # read green
	fixed ($t2, $t2)
	fixedMult ($t2, $t2, $t0)
	addu destG, destG, $t2

	lbu $t2, 2($t1) # read red
	fixed ($t2, $t2)
	fixedMult ($t2, $t2, $t0)
	addu destR, destR, $t2

	# move onto next pixel, so dx = 1
	li dx, 1
	fixed (dx, dx)
	
	# for_srcI end
	# end loop when we iterated over all horizontal pixels covered by projected destination pixel
	addiu srcI, srcI, 1
	lw $t0, iend
	ble srcI, $t0, for_srcI
	
	# move onto next pixel, do dy = 1
	li dy, 1
	fixed (dy, dy)
	
	# for_srcJ end
	# end loop when we iterated over all vertical pixels covered by projected destination pixel
	addiu srcJ, srcJ, 1
	lw $t0, jend
	ble srcJ, $t0, for_srcJ

	# round float accumulated values into ints
	round ($t0, destB)
	round ($t1, destG)
	round ($t2, destR)

	# if any color is somehow bigger than 0xFF due to approximation error, adjust it to fit into 1 byte
	ble $t0, 255, skip_adjust_blue
	li $t0, 255
skip_adjust_blue:
	ble $t1, 255, skip_adjust_green
	li $t1, 255
skip_adjust_green:
	ble $t2, 255, skip_adjust_red 
	li $t2, 255
skip_adjust_red:
   
   	# load address of color buffer and store colors into it
	la $t3, color_buf
	sb $t0, ($t3)
	sb $t1, 1($t3)
	sb $t2, 2($t3)

	# write 3 bytes of color buffer into output file
	li $v0, 15
	move $a1, $t3
	li $a2, 3
	syscall
	
	# for_destX end
	# end loop when we iterated over all horizontal pixels in destination image
	addiu destX, destX, 1
	lw $t0, dest_width
	blt destX, $t0, for_destX
	
	# as we move onto next row, add padding to the end of the pixel array row
	li $v0, 15
	la $a1, null_bytes
	lw $a2, padding_size
	syscall
	
	# for_destY end
	# end loop when we iterated over all rows in destination image
	addiu destY, destY, 1
	lw $t0, dest_height
	blt destY, $t0, for_destY
	
	# close output file
	li $v0, 16
	syscall
	
	# print some info
	printStr (done_msg)
	printStr (output_name)
	
	# end program
	b exit
	
	# one of the files couldnt be opened
error_opening:
	printStr (error_msg)

	# epilogue
exit:
	li $v0, 10
	syscall