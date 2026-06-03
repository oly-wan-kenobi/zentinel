#!/usr/bin/env python3
"""SEM-1a — TCE (Trivial Compiler Equivalence) measurement spike.

Evidence-gathering only; no production code. Answers the two questions that scope
SEM-1b (the TCE equivalence/dedup filter) per ZIR_IMPROVEMENTS.md "Beyond ZIR":

  (1) Over a sample of real src/ mutants, how many does TCE mark
      provably-equivalent (identical artifact to the original) or duplicate?
  (2) What is the per-mutant compile cost?

Method
------
The compiler-as-oracle artifact is the WHOLE-PROGRAM LLVM IR, emitted pre-link:

    zig build-exe -fstrip -femit-llvm-ir=... -fno-emit-bin \
        --global-cache-dir <fixed> --cache-dir <fixed> \
        --dep zentinel -Mroot=src/main.zig -Mzentinel=src/root.zig

Why this artifact and not the linked binary: the linked Mach-O embeds a per-link
random LC_UUID, so two builds of *identical* source differ — diffing the binary
would mark everything non-equivalent and catch nothing. The pre-link IR, with
`-fstrip` (drops debug-info paths) and FIXED global+local cache dirs (drops the
embedded cache path in `!DIFile`), is byte-deterministic for identical source
(verified: same source -> same sha256), so IR-identity is a valid TCE oracle.

Two roots, because lazy codegen is a soundness trap:
  * EXE root (main): only code statically reachable from `main` is emitted. A
    mutation in code NOT reached from main leaves the IR untouched -> looks
    "equivalent" even when it is a perfectly killable mutant.
  * FORCE-CODEGEN root: `test { refAllDecls(@import("<file>")); }` forces the
    file's top-level decls to be emitted. (Caveat surfaced by the spike: this is
    NON-recursive, so STRUCT METHODS are still not emitted — another hole.)

The spike runs the exe root over the sample, then re-checks every "equivalent"
verdict under the force-codegen root: if the IR moves there, the exe-root verdict
was a reachability artifact (a killable mutant), NOT a genuine equivalent.

Result recorded in ZIR_IMPROVEMENTS.md SEM-1a. Headline: in 80 sampled Debug-mode
mutants, ZERO confirmed genuine equivalents and ZERO duplicates; every IR-identical
verdict was an un-emitted (hence killable) site. Per-mutant IR emit ~1.0s warm.

Usage:  python3 scripts/sem1a_tce_spike.py [sample_n]
Requires Zig 0.16.0 on PATH. Operates on a throwaway copy of src/ under WORK.
"""
import json, hashlib, subprocess, time, sys, os, shutil

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = "/tmp/sem1a_tce"
SRC = WORK + "/src"
GC = WORK + "/gcache"; LC = WORK + "/lcache"; LC2 = WORK + "/lcache2"

def sh(cmd, cwd=WORK):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)

def setup():
    os.makedirs(WORK, exist_ok=True)
    if os.path.exists(SRC): shutil.rmtree(SRC)
    shutil.copytree(REPO + "/src", SRC)
    # config enabling the six stable mutators over src/**
    open(WORK + "/zentinel.toml", "w").write(
        '[project]\nname="sem1a"\nroot="."\ninclude=["src/**/*.zig"]\n'
        'exclude=[".zig-cache/**","zig-out/**","test/**"]\n'
        '[zig]\nversion="0.16.0"\nmodes=["Debug"]\n'
        '[backend]\ndefault="ast"\nexperimental=[]\n'
        '[mutators]\nenabled=["arithmetic_add_sub","arithmetic_mul_div",'
        '"equality_swap","comparison_boundary","logical_and_or","boolean_literal"]\n'
        '[test]\ncommands=["zig build test"]\ntimeout_ms=30000\n'
        '[report]\noutput_dir="zig-out/zentinel"\n')
    # build the zentinel CLI and list mutants
    r = sh(["zig","build-exe","--dep","zentinel","-Mroot=src/main.zig",
            "-Mzentinel=src/root.zig","-femit-bin="+WORK+"/zentinel"])
    assert os.path.exists(WORK+"/zentinel"), "CLI build failed:\n"+r.stderr
    r = sh([WORK+"/zentinel","--root",WORK,"list-mutants","--format","json"])
    json.dump(json.loads(r.stdout), open(WORK+"/mutants.json","w"))
    return json.loads(r.stdout)["mutants"]

def exe_ir():
    out = WORK+"/probe.ll"
    if os.path.exists(out): os.remove(out)
    r = sh(["zig","build-exe","-fstrip","-femit-llvm-ir="+out,"-fno-emit-bin",
            "--global-cache-dir",GC,"--cache-dir",LC,
            "--dep","zentinel","-Mroot=src/main.zig","-Mzentinel=src/root.zig"])
    if not os.path.exists(out): return False, r.stderr[:200]
    return True, hashlib.sha256(open(out,"rb").read()).hexdigest()

def force_ir(relfile):
    open(SRC+"/__probe.zig","w").write(
        'const F = @import("%s");\ntest { @import("std").testing.refAllDecls(F); }\n'
        % os.path.relpath(relfile, "src"))
    out = WORK+"/p.ll"
    if os.path.exists(out): os.remove(out)
    r = sh(["zig","test","--test-no-exec","src/__probe.zig","-fstrip",
            "-femit-llvm-ir="+out,"-fno-emit-bin","--global-cache-dir",GC,"--cache-dir",LC2])
    if not os.path.exists(out): return False, r.stderr[:200]
    return True, hashlib.sha256(open(out,"rb").read()).hexdigest()

def patch(f, m):
    data = open(f,"rb").read()
    bs,be = m["span"]["byte_start"], m["span"]["byte_end"]
    if data[bs:be].decode("utf-8","replace") != m["original"]: return None
    open(f,"wb").write(data[:bs] + m["replacement"].encode() + data[be:])
    return data

def main():
    mut = setup()
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 80
    step = max(1, len(mut)//N); sample = mut[::step][:N]
    ok, BASE = exe_ir(); assert ok, BASE
    print(f"baseline IR {BASE[:16]} sample={len(sample)}/{len(mut)} step={step}")
    seen = {}; cats = {k:0 for k in ("equivalent","duplicate","distinct","compile_error","patch_skip")}
    eqs = []; t0 = time.time()
    for m in sample:
        f = WORK+"/"+m["file"]; data = patch(f, m)
        if data is None: cats["patch_skip"]+=1; continue
        ok, res = exe_ir(); open(f,"wb").write(data)
        if not ok: cat="compile_error"
        elif res==BASE: cat="equivalent"; eqs.append(m)
        elif res in seen: cat="duplicate"
        else: cat="distinct"; seen[res]=m["id"]
        cats[cat]+=1
    dt = time.time()-t0
    print("exe-root verdicts:", cats, f"  mean {dt/len(sample):.2f}s/mutant")

    # Re-check exe-root "equivalents" under the sound force-codegen root.
    genuine = artifact = 0
    print(f"\nforce-codegen re-check of {len(eqs)} exe-root equivalents:")
    for m in eqs:
        if m["file"]=="src/cli.zig": print("  skip cli.zig (needs module)"); continue
        f = WORK+"/"+m["file"]
        ok0,base = force_ir(m["file"])
        data = patch(f, m)
        okm,mm = force_ir(m["file"]); open(f,"wb").write(data)
        v = "GENUINE-EQUIVALENT" if (ok0 and okm and mm==base) else "reachability-artifact (killable)"
        if v.startswith("GENUINE"): genuine+=1
        else: artifact+=1
        print(f"  {v:34} {m['file']:34} {m['operator']:18} {m['original']}->{m['replacement']}")
    if os.path.exists(SRC+"/__probe.zig"): os.remove(SRC+"/__probe.zig")
    print(f"\nCONFIRMED genuine equivalents: {genuine}   reachability-artifacts (killable): {artifact}")
    print("NB: 'genuine' here can still be a refAllDecls hole (struct methods are not"
          " force-emitted); inspect each before trusting it as truly equivalent.")

if __name__ == "__main__":
    main()
