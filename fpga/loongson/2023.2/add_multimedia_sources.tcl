# Run from the Vivado Tcl console after opening system_run.xpr.
set repo_root [file normalize [file join [file dirname [info script]] ../../..]]
set media_sources [list \
    [file join $repo_root IP AVP avp_async_fifo.v] \
    [file join $repo_root IP AVP avp_stream_dma.v] \
    [file join $repo_root IP AVP avp_i2s.v] \
    [file join $repo_root IP AVP avp_vga.v] \
    [file join $repo_root IP AVP avp_axi_controller.v] \
    [file join $repo_root IP VGA projectf display_timings.v] \
    [file join $repo_root IP PS2 opencores_host ps2_host.v]]

add_files -norecurse -fileset sources_1 $media_sources
update_compile_order -fileset sources_1
puts "Added LA32R I2S/VGA/PS2 sources. Generate S04/S05 and both clocks next."
