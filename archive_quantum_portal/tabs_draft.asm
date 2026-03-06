struc Tab
    .fd             resd 1     ; File descriptor for the background curl process (4 bytes)
    .padding        resd 1     ; Padding to align next member to 8 bytes 
    .buffer_offset  resq 1     ; Offset in the shared buffer (8 bytes)
    .buffer_ptr     resq 1     ; Pointer to buffer location (8 bytes)
endstruc
