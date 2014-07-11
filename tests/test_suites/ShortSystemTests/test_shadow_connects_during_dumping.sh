master_cfg="MFSMETARESTORE_PATH = $TEMP_DIR/metarestore.sh"
master_cfg+="|DUMP_METADATA_ON_RELOAD = 1"
master_cfg+="|PREFER_BACKGROUND_DUMP = 1"
master_cfg+="|MAGIC_DISABLE_METADATA_DUMPS = 1"

CHUNKSERVERS=1 \
	MASTERSERVERS=2 \
	USE_RAMDISK="YES" \
	MASTER_EXTRA_CONFIG="$master_cfg" \
	setup_local_empty_lizardfs info

# Instead of real mfsmetarestore, provide a program which hangs forever to slow down metadata dumps
cat > "$TEMP_DIR/metarestore.sh" << END
#!/bin/bash
touch "$TEMP_DIR/dump_started"
sleep 30 # Long enough to do the test, short enough to be able to terminate memchek within 60 s
touch "$TEMP_DIR/dump_finishing"
END
chmod +x "$TEMP_DIR/metarestore.sh"

m=${info[master0_data_path]} # master's working directory
s=${info[master1_data_path]} # shadow's working directory

# Generate some files
cd "${info[mount0]}"
touch file{1..20}
lizardfs_master_daemon reload                          # Start dumping metadata
wait_for 'test -e $TEMP_DIR/dump_started' '15 seconds'
touch file{30..40}
lizardfs_master_n 1 start                              # Connect shadow master during the dump
wait_for 'test -e "$s"/changelog.mfs.1' '15 seconds'   # Wait for shadow master to connect
touch file{50..60}

# Expect them to synchronize despite of the dump in progress
assert_less_than 40 $(get_changes "$m" | wc -l)    # checks that there are some non-empty changelogs
assert_equals 1 $(metadata_get_version "$m/metadata.mfs") # check that all the changelogs are needed
assert_success wait_for 'cmp "$m/metadata.mfs" "$s/metadata.mfs"' '30 seconds'
assert_success wait_for 'cmp <(get_changes "$m") <(get_changes "$s")' '30 seconds'
assert_file_not_exists "$TEMP_DIR/dump_finishing"

# Check if new changes are also being synchronised between metadata servers
rm file{50..60}
assert_success wait_for 'cmp <(get_changes "$m") <(get_changes "$s")' '30 seconds'