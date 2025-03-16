#name: Reset LAPS Password
#description: Reset the LAPS password for the current computer.
#execution mode: Combined
#tags: beckmann.ch

# Initiate a policy processing cycle.
Invoke-LapsPolicyProcessing -Verbose

# Initiate an immediate password rotation.
Reset-LapsPassword -Verbose
