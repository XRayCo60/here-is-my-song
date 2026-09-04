# smile

Temporary anonymous compute prototype for a local CPU/CUDA validation run.

## Files

- `smile.cpp` — complete CPU application: event engine, Persian teacher, dashboard and checkpoint
- `smile_cuda.cu` — CUDA validation core for the real normal/memory neuron VM
- `persian_words.tsv` — curated UTF-8 Persian dictionary (readable TSV)
- `my_words.tsv` — personal verified/suggested/blocked words; safe to edit
- `run.ps1` — local Windows build/run script
- `smile.exe` — prebuilt Windows CPU executable in the downloadable CPU package
- `brain.dat` — generated checkpoint

## Persian dictionary and personal suggestions

The base file is human-readable and sorted with Persian letter collation
(`آ ا ب پ ت ث ج چ ح خ د ذ ر ز ژ س ش ص ض ط ظ ع غ ف ق ک گ ل م ن و ه ی`):

```text
word<TAB>frequency<TAB>status<TAB>source_or_note
```

Membership comes from 81,063 POS-tagged entries in the curated Lilak spell-check lexicon; its 12,624 untagged/user entries were excluded. Subtitle frequency is only a statistical weight. The previous raw 155k subtitle-type dump was removed.

Put edits in `my_words.tsv`, not the generated base:

```text
نورومورفیک	10	suggested	نیازمند بازبینی
ایبوپروفین	10	verified	نام دارو
واژهغلط	0	blocked	غلط تایپی
```

- `verified`: trains dictionary and spelling judge
- `suggested`: visible for review but gives no training signal
- `blocked`: removes a base word

The output codec now contains only the 32 Persian letters, `آ`, space, and four common punctuation marks. Arabic hamza forms, digits, and noisy symbols were removed.

## Does the automatic teacher learn?

The old implementation did not: A/B runs produced identical event fingerprints because reward only changed mana credit. Checkpoint-v5 adds persistent causal `plasticity` that changes firing cadence/refractory/gating, so feedback now changes behavior.

It still did **not** win the clean-data A/B. Across three seeds (1000 neurons, 350 virtual seconds), automatic plasticity changed exact-word rate from 5.21% to 4.98% and average quality from 12.09 to 11.43; only the last-10-word quality rose slightly. Therefore automatic strength defaults to **0**: scoring and metrics remain active, but automatic behavioral modification is opt-in and experimental. This is an evaluator, not yet proven language training.

## First learning rung — paid rewiring (`--rewire`)

Section 33 of `ARCHITECTURE.md` in full. Short version:

`plasticity` could only change *how fast* a neuron fires, never *what it connects to*.
`--rewire` adds three things: a causal receipt on each **edge**, the ability for a neuron
to **buy** a move of its worst edge with ordinary mana, and rank-based starvation so that
persistently useless neurons actually die.

Two structural bugs surfaced doing this:

- **Selection was never firing.** Every run reported `dead: 0`. Neurons always got what they
  asked from the lobe pool, so `last_income` never went stale and the starvation path was
  unreachable. The mana economy was bookkeeping, not pressure.
- **An absolute hunger threshold causes a death wave.** The first attempt killed 801 of 1000
  neurons and produced zero words. The threshold is now rank-based (bottom 5% of a lobe's
  credit during famine), which is self-limiting. Population now settles at ~80% and holds.

`--holdout N` removes N% of the lexicon (deterministic FNV-1a split) from both the reward
path and the n-gram model, so the exact-word rate can be checked for generalization rather
than memorization.

### A/B result: negative

10 seeds, 1000 neurons, 600 virtual seconds, paired t-test (df=9, threshold 2.26):

| metric | off | on | diff | t |
|---|---|---|---|---|
| exact-word rate % | 7.18 ± 2.24 | 6.91 ± 2.77 | −0.27 | −0.22 |
| average quality | 11.83 ± 1.61 | 13.12 ± 2.54 | +1.29 | +1.12 |
| held-out rate % | 0.10 | 0.00 | −0.10 | −1.48 |
| words produced | 162.5 | 93.4 | **−69.1** | **−6.39** |

The only significant effect is a 43% drop in word output. Rewiring does not improve quality;
it makes the brain quieter. So `--rewire` defaults to **off**, like the automatic teacher.

Reproduce:

```bash
bench/ab.sh 10 600 1000
```

With the flag off, the engine is bit-identical to the previous build (verified by comparing
run fingerprints across seeds).

## Second learning rung — paid function mutation, silence penalty, talking teacher

Section 34 of `ARCHITECTURE.md` in full. Three new opt-in flags, all default **off**:

- **`--mutate`** — a punished neuron (plasticity < −1024) can pay **10 mana** (half its tank)
  to mutate **its own bytecode**: the program table is shared, so mutation first clones the
  program into a private copy, then changes exactly one instruction (nudge a numeric
  constant ±48, swap an ALU opcode, or swap a sense channel). Dead owners' slots are
  recycled. Rate cap: 0.5% of the population per second.
- **`--silence`** — staying quiet to avoid punishment no longer works. If no real word is
  closed for 10s (30s grace at start), each second applies a −2 mana fine through the same
  path as rewards (output-lobe pool drain + temporary income cut). Two brakes: a grace
  period after every word, and suspension while the output pool is below 40% — so the
  mouths can't be flogged to permanent silence.
- **`--teach-feed N`** — the automatic teacher finally *speaks*: every N virtual seconds it
  says one verified word through the same input codec a human uses. Until now the brain
  **never heard a real word** in headless runs (only its own mirror). Fed words are always
  outside the held-out set.
  **Removed from the standard recipe (§37):** telling the brain real words violates the
  project's core rule — the brain must discover by itself which words mean something, and
  the only allowed teaching channel is pain (mana). The flag stays in the code (default 0)
  for controlled experiments only; no standard run passes it anymore.

Mutation also exposed a latent VM bug: `INT_MIN / −1` (and `INT_MIN % −1`) in `OP_DIV`/
`OP_MOD` raises `SIGFPE` and kills the whole process. Seed programs never reach it (small
positive constants), mutated programs can — the first long run died exactly there. The
guards are complete now and the default path stayed bit-identical.

Checkpoint format is unchanged (`own_prog` is derived on load: `prog ≥ 10` means private);
save/load round-trip with live mutants was tested. With all new flags off the engine is
again **bit-identical** to the previous build (seeds 1/2 fingerprints match).

### A/B results (10 seeds, 1000 neurons, 600s, paired t-test df=9)

| configuration | exact % | avg quality | words | dead |
|---|---|---|---|---|
| baseline (no feed) | 7.18 ± 2.24 | 11.83 | 162.5 | 0 |
| + talking teacher | 7.93 ± 1.78 | 12.87 | 170.4 | 0 |
| teacher + rewire + silence + mutate | **4.84 ± 2.61** | 13.16 | **79.9** | 96.5 |
| teacher + silence + mutate (no rewire) | 7.21 ± 2.70 | 14.42 | 166.1 | 0 |

Reading:

- The **talking teacher alone** is a small, not-significant gain (+0.75 points).
- The **full combo with starvation is counterproductive**: rank-based starvation kills
  exactly the punished neurons that mutate (they sit at the bottom of the credit table),
  so mutations never get a fair trial — avg 32 mutations per run, 0 live private programs.
- **Without starvation, mutation actually flows** (~2030 mutations, ~20 live private
  programs per run) and the word-count collapse from rung 1 disappears (166 vs 170 words;
  rung 1's `--rewire` had dropped it to 93). Quality rises slightly (+1.55, not
  significant). Still no learning win.

### Long run — three hours alone with the teacher

`bench/longrun.sh` chains checkpointed segments and prints one `RESULT` line per segment:

```bash
FLAGS='--teach-feed 3 --silence --mutate' bench/longrun.sh 1 9 1200 1000
```

Result (seeds 1–2 with `--teach-feed 3 --silence --mutate`, plus a teacher-only control; each
segment = 20 virtual minutes; `bench/longrun.sh SEED 9 1200 1000`):

| seed 1 combo — exact % per segment | 9.7 | 5.6 | 7.1 | 0.0 | 2.3 | **15.3** | 0.0 | 0.0 | 11.3 |
|---|---|---|---|---|---|---|---|---|---|
| seed 2 combo — exact % per segment | 5.9 | 10.8 | 9.6 | 4.9 | 9.8 | 9.9 | 7.1 | 2.7 | 2.9 |
| control (teacher only) — exact % | 8.9 | 8.2 | 6.8 | 6.1 | 4.1 | 6.7 | 4.8 | 13.2 | 3.7 |

- **No reliable learning in three hours**, in either configuration. Exact-word rate stays in
  the same 0–15% noisy band it started in.
- **The control drifts slightly down** (mean ≈ 6.9%) — hearing words alone does nothing.
- **The combo runs are less stable, not more**: seed 1 oscillates wildly (words per segment
  19…242, exact 0%…15.3%); seed 2 holds quality high (avgQ ≈ 15 vs control ≈ 12) but its
  word output decays over the three hours (135 → ~34 words per segment) — even with the
  silence fine, the brain slowly retreats into quieter strategies.
- Mutation really flows and survives (private programs grow to 80+ and stay alive), so the
  mechanism works; what's missing is anything that **consolidates** a good mutant. Credit
  is smeared over ~256-neuron causal traces, so nothing teaches the network *which*
  mutation was the good one.

Reproduce the A/B tables:

```bash
ON_FLAGS='--teach-feed 3' bench/ab.sh 10 600 1000
COMMON_FLAGS='--teach-feed 3' ON_FLAGS='--silence --mutate' bench/ab.sh 10 600 1000
```

## Third learning rung — special mana and sprouting (`--sprout N`)

Section 35 of `ARCHITECTURE.md` in full. The evolutionary loop had variation (mutation)
and selection (the mana economy) but **no heredity** — a neuron that provably helped
produce correct words couldn't copy itself, so good paths were never amplified.

`--sprout N` closes the loop:

- Every neuron has a **separate savings counter** (`kmana`, "special mana") that can't be
  spent on anything else. Each participation in an **exactly-correct** word adds 1 (mouths
  excluded — they participate in every word, right or wrong, so their share isn't merit).
- When savings reach the threshold (try 5 or 10), the neuron zeroes its balance and
  **sprouts a copy of itself**. Inherited: kind, lobe, program (a mutant parent's private
  program is re-copied so later mutations don't drag the child along), wiring pattern,
  body memory, and **half the parent's ordinary mana** (cell division — no money printed).
  Not inherited: edge receipts, credit, plasticity, special mana. The child is born with a
  blank record and stands its own trial. Children are never mouths/ears (band 26) and sit
  next to the parent.
- Two brakes: ~1 sprout/second per 1000 neurons, and a 25%-of-base population cap. When
  the brain eventually understands meanings, this is the volume-control knob to turn off —
  it's a flag, not hardwired.

Checkpoint format `SMILE007` persists `kmana` + the base population; grown brains
(pop_base == N) continue across `--load` instead of being rebuilt. Bit-identical default
path verified. (One gotcha fixed along the way: `bench/smile-bench` must be rebuilt after
adding flags — stale binaries exit 2 on unknown options, silently.)

### A/B in a single 600s window: neutral

Both arms `--teach-feed 3 --silence --mutate`; on-arm adds `--sprout 5` (10 seeds, paired
t-test df=9):

| metric | without | with | diff | t |
|---|---|---|---|---|
| exact % | 7.21 ± 2.70 | 6.66 ± 1.98 | −0.55 | −0.51 |
| avg quality | 14.42 | 14.06 | −0.36 | −0.34 |
| words | 166.1 | 176.9 | +10.8 | +0.64 |
| held-out % | 0.22 | 0.36 | +0.14 | +1.05 |

Nothing significant — expected: amplifying good paths pays off over generations, not in
one window. Avg 20 sprouts per run (range 0–69), population up to ~1020.

### Long run — three hours with sprouting

```bash
FLAGS='--teach-feed 3 --silence --mutate --sprout 5' bench/longrun.sh 1 9 1200 1000
```

Result (seeds 1–2, `--sprout 5`; each segment = 20 virtual minutes; compare against the
rung-2 curves above which used identical flags minus sprouting):

| seed 1 +sprout — exact % | 10.5 | 5.0 | 6.5 | 6.1 | 14.3 | 0.0 | 7.6 | 0.0 | 7.1 |
|---|---|---|---|---|---|---|---|---|---|
| seed 1 +sprout — words | 143 | 222 | 138 | 33 | 105 | 1 | 66 | 10 | 56 |
| seed 2 +sprout — exact % | 4.4 | 7.0 | 9.5 | 6.1 | 7.0 | 0.0 | 4.7 | **22.2** | **22.2** |
| seed 2 +sprout — words | 137 | 128 | 200 | 181 | 43 | 11 | 43 | **9** | **9** |
| seed 2 +sprout — population | 1001 | 1012 | 1087 | 1116 | 1121 | 1121 | 1128 | 1134 | 1140 |

- **Seed 2 shows the first hint of the intended dynamics**: population keeps growing
  (1000 → 1140, descendants of exact-word producers), and by the last two segments
  precision jumps (22% exact, avgQ 31–37 vs the control's 2.9% / 15.7) — **but word volume
  collapses to 9 per segment**. The brain becomes selective: it says little, and what it
  says is much better. Whether that's "learning to speak well" or "retreating into
  repeating a few safe words" needs a next experiment (track word diversity).
- **Seed 1 is unchanged** from its no-sprout twin — same instability, same decay.
- The word-volume decay over hours is still the dominant unsolved problem; sprouting
  changes *what* survives, not the slide toward silence.

## Repetition is memory, not evasion — judge fix (band 36)

The judge used to take **−18 per repeat** of a word. That was a major driver of the
word-volume decay: the brain fled repetition into either novel garbage or silence. But
repetition means the word-producing path stayed stable — the memory works — which is
exactly what should be *hardening*. Per the design intent ("we want the paths that produce
meaningful words to become engraved"):

- Spaced recall (word seen 1–3 times in the last 24 words, not consecutive): **+5**
- Back-to-back streak: **−5 × streak** (small — that's spam, not memory)
- Excessive (more than 3 in the window): **−5 × excess** (small)

### First significantly positive result of the project

10 seeds, 600s, identical flags on both arms (`--teach-feed 3 --silence --mutate --sprout 5`);
only the judge differs (old binary vs new, paired t-test df=9):

| metric | old judge | new judge | diff | t |
|---|---|---|---|---|
| avg quality | 14.06 | **20.84** | **+6.78** | **+8.31** |
| last-10-words quality | 13.30 | **24.18** | **+10.88** | **+3.88** |
| exact % | 6.66 | 8.31 | +1.65 | +1.59 |
| words | 176.9 | 185.0 | +8.1 | +0.38 |

Quality jumped **without** losing volume — a real improvement, not quiet-hiding (the trap
rungs 1–2 fell into). Last-words quality nearly doubling is consistent with paths gradually
hardening. Word diversity stays at 65% (avg 121 distinct words per run) — memory without
spam-farming. New `distinct=` key in the RESULT line measures this.

<!-- NEWJUDGE_LONGRUN_RESULTS -->

### Long run (3 virtual hours, 9×1200s, sprouting+mutate+silence), new judge vs old

Seed 2: the old judge's word count collapsed to **9 words** by hours 2–3 (with a misleading
22% exact on those 9 words — near-silence). New judge: 135, 116, 291, 34, 113, 83, 45, 41, 38
— gradual decline from peak, no collapse to zero; avg quality stays in 16–27 the whole way.

Seed 1: old judge crashed to 1 and 10 words mid-run; new judge: 305, 18, 103, 167, 205, 123,
178, 18, 20 — mean exact 6.3% → 8.3%, no crash but a low-volume tail remains.

Bottom line: the heavy repeat penalty was a main driver of the word-volume decay. Removing
it kept quality stable across the full run, stopped the collapse to ~9 words, and eliminated
the "reward-collecting silence" artifact. A slow late-hours volume decline remains — next
suspect: accumulated negative plasticity.

## Run on Windows (PowerShell) — capped CPU, no laptop sleep

`bench/win-longrun.ps1` is the Windows twin of `bench/longrun.sh`. It:

- uses the **prebuilt `bench\smile-bench.exe`** that ships in the repo (statically
  linked, imports only OS DLLs + UCRT — no compiler install needed; `-Rebuild`
  recompiles from source with MinGW-w64 g++ if you have one),
- runs the 9×1200s segmented long run with the **pain-only flag set**
  (`--silence --mutate --sprout 5` — no `--teach-feed`; §37: the only teaching channel
  is pain, the brain must find meaningful words by itself), chaining checkpoints via
  `brain.dat`,
- caps the process to half your logical cores (`-CpuCap`, default 0.5) and sets priority
  BelowNormal, so the laptop stays responsive,
- keeps the system awake for the whole run via `SetThreadExecutionState` and reverts it
  automatically at the end (or on Ctrl+C),
- appends each segment's RESULT line to `longrun_win_seed<N>.txt` and prints a summary.

The prebuilt exe is clang/zig-built for x86_64-w64-mingw32 (verified: compiles clean,
imports only WS2_32/KERNEL32/SHELL32/UCRT). If `winget` times out on msstore (some
networks), keep `--source winget`: `winget install --source winget -e --id
BrechtSanders.WinLibs.POSIX.UCRT`.

**Scale (§38):** runs now default to **32000 neurons** (the real project scale; all
earlier witnesses were 1000-neuron pilots). Expect ~24× slower than 1000: on the
8-core laptop with the default 50% cap, one 1200s segment ≈ 70–80 min wall and the
full 9×1200s run ≈ 9–12 h — an overnight run; add `-KeepDisplayOn`. For a quick
calibration first: `-Segs 1 -SegSecs 300` (≈ 20 min). `-Neurons 1000` still works
for pilot runs.

### First laptop run (8 logical cores, 50% cap, prebuilt exe)

Seed 1, full 9×1200s in 21 min wall (user's machine, no compiler installed): mean
exact% 5.4, mean words 92, mean avgQ 21.4, pop 1000→1030. Word volume never collapsed
(min 48 per segment, run ends at 115 words) and avgQ stays 18–26 throughout — the
new-judge signature reproduces on different hardware/compiler. (Windows runs are not
bit-identical to Linux builds — FP differences diverge trajectories — only the
statistical pattern is comparable.)

Note: this run was made with the **old** recipe (`--teach-feed 3 ...`) — it is the last
teach-fed witness. Runs after §37 are pain-only and not directly comparable; how much of
the learning came from hearing words vs. from pain is itself the next experiment.

Run from the repo root:

```
powershell -NoProfile -ExecutionPolicy Bypass -File bench\win-longrun.ps1            :: seed 1
powershell -NoProfile -ExecutionPolicy Bypass -File bench\win-longrun.ps1 -Seed 2    :: seed 2
```

Useful switches: `-Segs 3 -SegSecs 600` (shorter run), `-CpuCap 0.25` (stricter cap),
`-KeepDisplayOn` (screen stays on), `-Rebuild` (recompile), `-NormalPriority`.

### Live dashboard (browser) — `bench/win-dashboard.ps1`

The longrun script intentionally runs a **headless fixed 9-segment experiment** (that's
why it exits by itself and prints numeric RESULT lines). To watch the brain live instead:

```
powershell -NoProfile -ExecutionPolicy Bypass -File bench\win-dashboard.ps1
```

The browser opens automatically at http://localhost:8420 and the sim runs until you stop
it. Same CPU cap, priority, and sleep prevention. The dashboard's save button writes
`brain.dat` (pause + save); run again with `-Load` to continue that brain. Clean exit:
press save in the dashboard first, then Ctrl+C in PowerShell.

Notes:

- Idle sleep is prevented, but closing the lid still sleeps the laptop — keep the lid open
  (or set "When I close the lid" to *Do nothing* in Power Options).
- The sim spawns a worker pool sized to all logical cores; the affinity cap is what
  guarantees it never exceeds 50% total CPU.

## CUDA test on Windows

Requirements:

1. NVIDIA driver (`nvidia-smi` must work)
2. Visual Studio 2022 Build Tools with **Desktop development with C++**
3. CUDA Toolkit (`nvcc --version` must work)

Toolkit compatibility matters:

- GTX 900 and GTX 10 series (compute capability below 7.5): use **CUDA 12.9**. CUDA 13 removed offline compilation for these GPUs.
- GTX 16 series (Turing, 7.5): CUDA 12.9 or CUDA 13.x.

Open PowerShell in this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Gpu
```

CUDA-test defaults:

```text
neurons       32,000 (fixed real brain, no synthetic duplication)
GPU ceiling   70% (hard maximum; configurable from 10% to 70%)
duration      120 seconds
device        0
```

The first CPU run after this size change archives any existing checkpoint as `brain-before-32k-<date>.dat` and starts a clean 32k brain. Later runs continue the new `brain.dat`. The engine also rejects a loaded checkpoint whose neuron count differs from the requested count.

Measured in the two-logical-CPU sandbox, the current 32k build used about **98 MiB peak RAM** and created a **12.8 MiB checkpoint**. Building the brain, running one virtual second and saving took **3.1 wall seconds**, processing 4.73M events with zero VM faults.

Custom duration or a lower ceiling (10–70%):

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Gpu -GpuLimit 70 -Seconds 300
```

The script detects the GPU compute capability, builds the native `sm_XX` target, runs the CUDA core and prints every half second:

- actual NVML GPU utilization and the configured ceiling
- controller duty cycle
- temperature
- virtual-time speed
- firing rate
- signals and dropped signal count

### Important interpretation

`70%` is a **hard ceiling**, not fake target padding. With only 32,000 real neurons, a strong GTX may naturally remain below 70%. The program does not duplicate work just to make Task Manager show a larger number.

The corrected source has been compiled and linked with the real NVIDIA NVCC 13.3 compiler for `sm_75`, and the resulting binary's `--help` path was executed. That proves the CUDA translation unit builds for Turing; it does **not** claim a GPU runtime test. GTX 900/10-series hardware still needs the documented CUDA 12.9 target-machine build and run.

On Windows Task Manager select the GPU graph named **CUDA** or **Compute**, not only `3D`. The console's NVML value is the primary measurement.

A thermal guard reduces duty at 85°C and stops at 90°C.

## What the CUDA validation core really executes

- 1 ms dependency windows
- CUDA Graph launch path when supported
- the same linear bytecode programs for normal neurons
- the same semi-linear bytecode programs and 1 KB local memory for memory neurons
- 20/40 real edges per neuron with 1–20 ms delay
- signal ring, input freshness and output masks
- per-neuron mana, firing cost, upkeep, lobe pools and delayed return
- fixed 14-neuron mouth bottleneck
- normal/memory population on GPU; giant population is counted as host-side work

This is not a matrix-multiplication stress test. It validates the mass-neuron CUDA architecture. The first CUDA run intentionally does **not** replace the complete CPU application yet: teacher scoring, exact causal feedback, dashboard and CPU↔giant signal exchange stay in `smile.cpp` until the hardware test confirms kernel correctness and throughput.

## Command-line help

Both binaries print their options and exit:

```bash
./smile --help
./smile-gpu --help
```

An unknown option is a hard error (exit code 2) instead of being silently ignored.

The dashboard serves the page only on `/` and `/index.html`; every other unknown path
returns a real `404`.

## CPU fallback

The full 32k CPU application is now the default while no strong GPU test machine is available:

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1
```

`-Cpu` remains accepted as an explicit alias.

The complete CPU package can use its bundled `smile.exe` without a compiler. If `g++` is installed, the runner rebuilds it from `smile.cpp`. It then continues a matching `brain.dat` when present and opens:

```text
http://localhost:8420
```

Manual build on Linux/macOS:

```bash
g++ -O2 -std=c++17 -pthread smile.cpp -o smile
./smile --neurons 32000 --port 8420 --words persian_words.tsv
```

Manual CUDA build on Linux (add your GPU architecture):

```bash
nvcc -O3 -std=c++17 -arch=sm_75 smile_cuda.cu -o smile-gpu -ldl
./smile-gpu --neurons 32000 --gpu-limit 70 --seconds 120
```

## Test report to keep

After the run, keep or send:

```powershell
nvidia-smi
nvcc --version
```

and the full `smile-gpu.exe` console output. The critical fields are GPU utilization, virtual speed, signal drops, temperature and compute capability.

## Licensing

`persian_words.tsv` is derived from the Lilak dictionary (Apache-2.0) and from
subtitle frequencies (CC BY-SA 4.0). Attribution and the resulting obligations are
recorded in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). The project's own
source files still have no declared license — add a `LICENSE` file before publishing.
