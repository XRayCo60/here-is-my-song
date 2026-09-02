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
