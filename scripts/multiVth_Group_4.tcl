proc create_priority_list {vt} {
    set all_cells [get_cells -quiet -filter "lib_cell.threshold_voltage_group == ${vt}VT"]
    set priority_list [list]
    foreach_in_collection cell $all_cells {
        set this_cell_list [list $cell]
        set this_wrst_path [get_timing_paths -through $cell]
        set this_slack [get_attribute $this_wrst_path slack]
        # set pins [get_pins -of_object $cell -filter "direction == out"]
        # set fanout 0
        # foreach_in_collection pin $pins {
        #     puts $pins
        #     set fanout [get_attribute $pin max_fanout]
        # }
        
        # set heuristic [expr {$this_slack / $fanout}]
        
        # puts "cell: $cell slack: $this_slack fanout: $fanout heuristic: $heuristic"
        set heuristic $this_slack
        lappend this_cell_list $heuristic
        lappend priority_list $this_cell_list

    }
    set priority_list [lsort -index 1 -real $priority_list]
    return [lreverse $priority_list]
}

proc swap_vt {cell original_vt new_vt} {
    set library_name "CORE65LP${new_vt}VT"
    set ref_name [get_attribute $cell ref_name]
    regsub "_L${original_vt}" $ref_name "_L${new_vt}" new_ref_name
    size_cell $cell "${library_name}/${new_ref_name}"
    return
}

proc binary_swap {original_vt new_vt} {
    # case 1 swap L to H then L to S
    # case 2 swap L to S then S to H
    # if the number of swaps in the current cycle is 0, return
    set priority_list [create_priority_list $original_vt]
    set percentage 0.5
    set vt_cells [get_cells -quiet -filter "lib_cell.threshold_voltage_group == ${original_vt}VT"]
    set num_cells [sizeof_collection $vt_cells]
    set num_swaps [expr {int($num_cells * $percentage)}]
    while {$num_swaps > 0} {
        set success 0
        set swapped_cells [list]
        ##########################################################################
        #                          LOGIC FOR SWAPPING                            #
        ##########################################################################
        # swap $num_swaps cells according to priority list
        for {set i 0} {$i < $num_swaps} {incr i} {
            set cell [lindex [lindex $priority_list $i] 0]
            swap_vt $cell $original_vt $new_vt
            # update swapped_cells list
            lappend swapped_cells $cell
        }

        # call this to update the timing of the combinational circuit (recalculate slack foreach cell)
        update_timing -full
        # get critical path with slack lesser than 0
        # if no such path exists, set success to 1
        set result_timing [get_timing_paths -slack_lesser_than 0.0 -max_paths 1]
        if {[sizeof_collection $result_timing] == 0} {
            set success 1
        }

        if {$success} {
            # update priority_list
            set priority_list [create_priority_list $original_vt]
        } else {
            # revert operations using swapped_cells list
            for {set i 0} {$i < $num_swaps} {incr i} {
                set cell [lindex $swapped_cells $i]
                swap_vt $cell $new_vt $original_vt
            }
        }
        # update next cycle's number of swaps
        set percentage [expr {$percentage / 2}]
        set num_swaps [expr {int($num_cells * $percentage)}]
    }
    return
}

proc linear_swap {step original_vt new_vt} {
    set priority_list [create_priority_list $original_vt]
    set vt_cells [get_cells -quiet -filter "lib_cell.threshold_voltage_group == ${original_vt}VT"]
    set num_cells [sizeof_collection $vt_cells]
    set index 0
    # set next_step 0
    set consecutive_fails 0
    set skipped_cells 0
    while {$index < $num_cells} {
        set success 0
        set swapped_cells [list]
        for {set i $skipped_cells} {$i < [expr {$skipped_cells + $step}]} {incr i} {
            if {$i >= $num_cells} {
                break
            }
            set cell [lindex [lindex $priority_list $i] 0]
            swap_vt $cell $original_vt $new_vt
            lappend swapped_cells $cell
        }
        update_timing -full
        set result_timing [get_timing_paths -slack_lesser_than 0.0 -max_paths 1]
        if {[sizeof_collection $result_timing] == 0} {
            set success 1
        }

        if {$success} {
            # update priority_list
            set consecutive_fails 0
            set priority_list [create_priority_list $original_vt]
        } else {
            # revert operations using swapped_cells list
            for {set i 0} {$i < [llength $swapped_cells]} {incr i} {
                set cell [lindex $swapped_cells $i]
                swap_vt $cell $new_vt $original_vt
            }
            # update consecutive_fails
            incr consecutive_fails
            if {$consecutive_fails == 2} {
                break
            }

            # update index by step/2
            # update skipped_cells by step/2
            # set next_step [expr {int(ceil($step / 2))}]
            # set skipped_cells [expr {$skipped_cells + $next_step}]
            # set index [expr {$index + $next_step}]
            set skipped_cells [expr {$skipped_cells + $step}]
        }
        # update index by step
        set index [expr {$index + $step}]
        # print debug info
        puts "index: $index skipped_cells: $skipped_cells"
        puts "step: $step"
        puts "consecutive_fails: $consecutive_fails"
        puts "------------------------------------------------"
    }
}

proc logarithmic_decrease {start_value n end_value} {
    set log_sequence {}
    
    set log_start [expr {log($start_value) / log(10)}]
    set log_end [expr {log($end_value) / log(10)}]
    
    for {set i 0} {$i < $n} {incr i} {
        set t [expr {$i / double($n - 1)}]
        set log_val [expr {pow(10, (1 - $t) * $log_start + $t * $log_end)}]
        lappend log_sequence [expr {int(ceil($log_val))}]
    }
    
    return $log_sequence
}

proc multiVth {} {
    set case1 0
    if {$case1} {
        binary_swap L H
        binary_swap L S
    } else {
        binary_swap L S
        binary_swap S H
        binary_swap L S
        set cells [get_cells]
        set num_cells [sizeof_collection $cells]
        set steps [lrange [logarithmic_decrease $num_cells 9 3] 5 8]
        # {11 5 2} gets us 4 points
        foreach step $steps { 
            linear_swap $step L S
            linear_swap $step S H
            linear_swap $step L S
        }
    }
    return 1
}

# binary_swap L H
