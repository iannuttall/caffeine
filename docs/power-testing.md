# Test Caffeine against real Mac power states

Unit tests cover the policy that chooses each power assertion. The scripts in this guide check whether macOS accepted those assertions and whether work keeps running during a real screen-off or lid-closed test.

The guided tests write raw timestamp samples and a summary to `.build/power-tests/`. A one-second heartbeat proves the shell was still being scheduled. A large gap means the Mac slept or stopped scheduling work.

The scripts also look for another process holding the same kind of sleep assertion. A second sleep-prevention app would make a passing result meaningless. Stop the listed process and rerun the test. Set `CAFFEINE_TEST_ALLOW_COMPETITORS=1` only when you deliberately want to measure the whole setup rather than Caffeine on its own.

## Check the current assertions

Turn Caffeine on, then run:

```sh
make power-check
```

This check does not change the display or any settings. It finds the running Caffeine process and checks its assertion ownership against the current Power settings. The check fails if a similarly named process owns the assertion instead.

## Check work while the screen is off

Run the screen test from a visible terminal:

```sh
make power-test-screen
```

Press Return when prompted. The script asks macOS to switch the display off, then keeps recording heartbeat samples. Wait at least 30 seconds, wake the display, and press Return again.

Forced display sleep is intentional here. It lets the test cover an unattended setup even when the normal Caffeine setting keeps the display lit.

## Check work while the lid is closed

Connect power and turn on closed-lid mode in Caffeine settings. Run:

```sh
make power-test-lid
```

Follow the prompts, close the lid for at least 30 seconds, then reopen it. The report checks that the monitor saw a closed lid and that the heartbeat continued without a sleep-sized gap.

This result only applies to the Mac and connections used for that run. macOS and the hardware still decide whether closed-lid work is allowed. Test again after a major macOS update or when changing the dock, power adapter, or external display setup.

## Include a network probe

Set a stable URL you control when network access matters to an agent run:

```sh
CAFFEINE_TEST_URL=https://example.com make power-test-lid
```

The script sends one request about every five seconds. It passes the network check when at least 80 percent of requests return an HTTP status from 200 through 399. Do not put secrets or access tokens in the test URL.

These optional settings change the test limits:

```sh
CAFFEINE_TEST_MIN_SECONDS=60
CAFFEINE_TEST_MAX_GAP=5
CAFFEINE_TEST_MIN_NETWORK_SUCCESS=90
```

## Read a result

A passing 60-second run should look close to this:

```text
Elapsed: 63s
Heartbeat samples: 62
Largest scheduling gap: 2s
PASS: Work kept running without a sleep-sized gap.
Network probes: 12/12 (100%)
Result: PASS
```

Open `summary.txt` first. `samples.tsv` contains each heartbeat and observed lid state. `network.tsv` contains each optional HTTP probe. `metadata.txt` records the macOS version, hardware string, battery state, and test limits. `assertions-before.txt` records every process that could affect the result.
