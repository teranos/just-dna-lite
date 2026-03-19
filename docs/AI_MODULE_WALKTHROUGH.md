# AI Module Creator — Walkthrough & Examples

This document covers the Module Creator system end-to-end through four concrete, documented scenarios. For the technical spec (DSL format, compiler, registry API, agent architecture), see [AI_MODULE_CREATION.md](AI_MODULE_CREATION.md).

---

## How it works in practice

The Module Creator is a chat interface in the **Module Manager** tab. You type a description or upload research papers (PDF, CSV, Markdown, plain text — up to 5 files), pick a mode, and hit Send. The system writes a validated annotation module and loads it into an editing slot. You review it, optionally iterate via follow-up messages, and click **Register** when you're satisfied.

Two modes are available:

### Simple mode — single agent, ~2 minutes

A single Gemini Pro agent handles everything: queries biomedical databases (EuropePMC, Open Targets, BioRxiv, Ensembl), extracts variants with per-genotype weights, validates the output, writes `module_spec.yaml` + `variants.csv` + `studies.csv` + `MODULE.md`, and optionally generates a logo. If validation fails, the agent self-corrects and retries up to 10 iterations.

Good for: single well-defined papers, quick iteration, simple trait panels.

### Research team mode — multi-agent, ~5–13 minutes

A coordinated team of agents:

| Agent | Role | Model |
|-------|------|-------|
| PI (Principal Investigator) | Delegates tasks, synthesizes consensus, writes the final module, calls all write/validate/register tools | Gemini Pro |
| Researcher 1 | Independent literature research via BioContext MCP. Always present. | Gemini Pro |
| Researcher 2 | Same role, different LLM — model diversity reduces systematic blind spots. Present if `OPENAI_API_KEY` is set. | GPT |
| Researcher 3 | Same role, third perspective. Present if `ANTHROPIC_API_KEY` is set. | Claude Sonnet |
| Reviewer | Checks variant integrity, provenance, weight consistency, PMID validity via Google Search. | Gemini Flash |

Minimum team (Gemini key only): PI + 1 Researcher + Reviewer = 3 agents.
Maximum team (all three keys): PI + 3 Researchers + Reviewer = 5 agents.

The PI dispatches all Researchers simultaneously. Each independently queries the databases. The PI then synthesises by consensus:
- Variants confirmed by ≥2 researchers → high confidence → include
- Variants from only one researcher → scrutinise; omit unless ≥2 strong PMIDs support them
- Weight disagreements → use median estimate

The synthesised draft goes to the Reviewer, which fact-checks via Google Search and returns a structured `ERRORS / WARNINGS / OK` report. The PI fixes all errors, addresses warnings, then writes and registers the module.

The Reviewer may be called multiple times in a single run for distinct purposes: allele lookups (using Google Search as a factual oracle), PMID resolution (finding the correct citation for an uploaded PDF), and the final QC review.

There are no human-approve/reject steps between phases. After completion, the module is in the editing slot and you can iterate via follow-up chat.

Good for: complex topics spanning multiple papers, large variant sets from GWAS supplementaries, cases where you want cross-model validation.

---

## Module file structure

Every annotation module consists of three required files plus optional documentation and logo. The `module_spec.yaml` uses a nested structure:

```yaml
schema_version: "1.0"

module:
  name: my_module           # lowercase, underscores only
  version: 1                # integer, auto-bumped on edits
  title: "My Module"        # human-readable title in UI
  description: "..."        # one-liner for module cards
  report_title: "..."       # section title in PDF/HTML reports
  icon: heart-pulse         # see pi.yaml for icon catalog
  color: "#21ba45"          # hex color

defaults:
  curator: ai-module-creator
  method: literature-review  # literature-review | gwas | clinvar-review | expert-curation
  priority: medium           # low | medium | high

genome_build: GRCh38        # GRCh38 only — the platform does not support GRCh37
```

`variants.csv` has one row per (rsid, genotype) combination. `studies.csv` links rsids to PMIDs with population, p-value, conclusion, and study design.

---

## Scenario 1 — Solo agent: `familial_longevity`

**Source:** Putter et al. (2025), "Rare longevity-associated variants including a reduced-function mutation in cGAS, identified in multigenerational long-lived families" (bioRxiv, DOI: 10.1101/2025.12.04.689698)

**User input:**
```
I want you to create a module based on the attached articles
```
(with `Putter_longevity_variants_21.pdf` attached, single agent mode selected)

**Total runtime: ~107 seconds**

### What the agent did

| Time | Action | Detail |
|------|--------|--------|
| 0.0s | Start | Gemini Pro agent + BioContext MCP (30+ tools) + 5 module-writer tools loaded |
| 12.7s | `query_open_targets_graphql` | Queried Open Targets for variant–disease associations on CGAS gene |
| 23.0s | `get_europepmc_articles` | Searched EuropePMC for supporting cGAS-STING and cellular senescence literature |
| 28.9s | `get_biorxiv_preprint_details` | Fetched full preprint metadata (DOI, authors, abstract) |
| 56.4s | `get_europepmc_articles` | Second search for linkage variants: SH2D3A, RARS2, SLC27A3 |
| 79.5s | `write_spec_files` | Wrote `module_spec.yaml` + `variants.csv` (12 rows, 4 genes) + `studies.csv` |
| 85.0s | `validate_spec` | **VALID** — 12 variant rows, 4 unique rsids, 2 categories |
| 93.8s | `write_module_md` | Wrote `MODULE.md` with design decisions and changelog |
| 106.5s | `generate_logo` | Attempted logo generation (API error — model unavailable; noted in log) |
| ~107s | **Complete** | Module in editing slot |

### Key decisions the agent made

- Identified **cGAS rs200818241** (D452V missense) as the primary variant. Assigned +0.8 (heterozygous) and +1.2 (homozygous) based on functional evidence that the T→A mutation destabilises the cGAS protein and dampens cGAS-STING innate immune signalling, delaying cellular senescence.
- Added three supporting rare variants from Leiden Longevity Study linkage analysis (**SH2D3A rs146711285**, **RARS2 rs1209730474**, **SLC27A3 rs535256255**) with more conservative weights (+0.5/+1.0) reflecting co-segregation signal without individual functional validation.
- Chose `heart-pulse` icon and teal (`#00b5ad`) colour — appropriate for longevity/protective traits.
- Used the extended CSV format with genomic coordinates (`chrom`, `start`, `ref`, `alts`) and `priority` columns alongside the standard fields.

### Final output

`module_spec.yaml`:
```yaml
schema_version: "1.0"

module:
  name: familial_longevity
  version: 1
  title: "Familial Longevity & cGAS-STING Signalling"
  description: "Rare protective variants in cGAS and other genes associated with familial longevity and delayed cellular senescence."
  report_title: "Familial Longevity & Cellular Senescence"
  icon: heart-pulse
  color: "#00b5ad"

defaults:
  curator: ai-module-creator
  method: literature-review
  priority: medium

genome_build: GRCh38
```

`variants.csv` (excerpt):
```csv
rsid,chrom,start,ref,alts,genotype,weight,state,conclusion,priority,gene,phenotype,category
rs200818241,6,74135164,T,A,T/T,0,neutral,"Normal cGAS-STING activation; typical cellular senescence rates.",high,CGAS,Familial longevity,Immunity & Senescence
rs200818241,6,74135164,T,A,A/T,0.8,protective,"Heterozygous for the rare D452V missense variant. Dampens cGAS-STING signalling, delays cellular senescence, and is associated with familial longevity.",high,CGAS,Familial longevity,Immunity & Senescence
rs200818241,6,74135164,T,A,A/A,1.2,significant,"Homozygous for the rare D452V missense variant. Significantly reduces cGAS protein stability and dampens cGAS-STING signalling, extending cellular lifespan.",high,CGAS,Familial longevity,Immunity & Senescence
```

12 rows total across 4 genes (CGAS, SH2D3A, RARS2, SLC27A3), 3 genotype rows per variant, in 2 categories (Immunity & Senescence, Longevity & Healthspan). **No manual edits required.**

---

## Scenario 2 — Research team: `latest_longevity` v1

**Sources:**
- Putter et al. (2025) — cGAS longevity variant and linkage panel (PMID 41427385)
- Sheikholmolouki et al. (2025) — SIRT6 rs117385980 and its antagonistic pleiotropic relationship with frailty and extreme longevity (PMID 41249831)

**User input:**
```
Create a latest_longevity module, based on the attached articles. Let the module icon contain year 2025.
```
(two PDFs attached, Research Team mode selected)

**Total runtime: ~461 seconds (~7.7 minutes)**

### Phase 1 — Parallel research (0–136s)

The PI dispatched identical research tasks to all three Researchers simultaneously at t=21.5s. Each researcher independently queried EuropePMC, Open Targets, and BioRxiv:

| Time | Actor | Action |
|------|-------|--------|
| 21.5s | PI | `delegate_task_to_member → researcher-1` (Gemini) |
| 21.5s | PI | `delegate_task_to_member → researcher-2` (GPT-4.1) |
| 21.5s | PI | `delegate_task_to_member → researcher-3` (Claude Sonnet) |
| 23.5s | R1, R2, R3 | All three spin up BioContext MCP tool stacks in parallel |
| 72.7s | R1 | `get_europepmc_articles` — searched for SIRT6 rs117385980 literature |
| 74.6s | R1 | Confirmed PMID 41249831 (SIRT6 frailty study) |
| ~52–110s | R2, R3 | Parallel queries on Putter et al. variants |
| 136.5s | PI | All three researcher tasks complete |

### Phase 2 — Consensus synthesis and review (136–234s)

The PI compared outputs and applied consensus rules:
- **High confidence** (≥2 researchers agreed): cGAS rs200818241, SIRT6 rs117385980, linkage variants (NUP210L, SLC27A3×2, CD1A, IBTK×2, RARS2×2, SH2D3A)
- **Weight decisions**: cGAS het +0.8/hom +1.2 (functional evidence); SIRT6 het −0.5/hom −1.0 (inverse association with extreme age, stop-gained variant — antagonistic pleiotropy); linkage variants +0.4–0.5 (conservative, no individual functional validation)

At t=175.7s, the draft went to the Reviewer. The Reviewer used Google Search and returned:
- Confirmed cGAS rs200818241 as well-supported across multiple sources
- Confirmed SIRT6 rs117385980 antagonistic pleiotropy interpretation
- Flagged linkage variants (NUP210L, SLC27A3, CD1A, IBTK, RARS2, SH2D3A) as single-study findings — recommended conservative weights, which the PI retained

### Phase 3 — Output generation (234–461s)

| Time | Actor | Action |
|------|-------|--------|
| 275.6s | PI | `write_spec_files` — 33 variant rows, 11 rsids, 8 genes |
| 280.1s | PI | `validate_spec` — **VALID** |
| 288.9s | PI | `write_module_md`, `generate_logo`, `register_module` — launched in parallel |
| 461.3s | PI | All complete. Logo: 2025 genetics motif, teal/green. Module registered. |

### Final output

`module_spec.yaml`:
```yaml
schema_version: "1.0"

module:
  name: latest_longevity
  version: 1
  title: "Latest Longevity"
  description: "Latest rare and protective variants linked to extreme longevity and frailty in 2025."
  report_title: "Latest Longevity Genetics"
  icon: heart-pulse
  color: "#21ba45"

defaults:
  curator: ai-module-creator
  method: literature-review
  priority: medium

genome_build: GRCh38
```

`variants.csv`: 33 rows across 11 rsids in 8 genes across 2 categories:
- *Familial Longevity* (10 rsids across 7 genes × 3 genotypes): CGAS, NUP210L, SLC27A3 (×2 variants), CD1A, IBTK (×2 variants), RARS2 (×2 variants), SH2D3A
- *Frailty and Longevity* (1 rsid × 3 genotypes): SIRT6

`studies.csv`: 11 rows linking all variants to PMID 41427385 and PMID 41249831.

Note on SIRT6: rs117385980 is a stop-gained variant showing **antagonistic pleiotropy** — associated with frailty risk in the general population but depleted in individuals over 80. The agent correctly assigned negative weights (−0.5 het, −1.0 hom) reflecting its inverse association with extreme longevity.

**No manual edits required.**

---

## Scenario 3 — Research team: `latest_longevity` v2 (iterative update)

With `latest_longevity v1` loaded in the editing slot, the user uploaded a third paper and its large supplementary data:

**Sources:**
- Dinh et al. (2025), "Genetic links between multimorbidity and human aging" — multivariate GWAS identifying shared cardiometabolic liability (mvARD) inversely correlated with extreme longevity

**User input:**
```
I want now to update the module based on this article and supplementary materials for it (contains ~260 rsids).
```

**Total runtime: ~418 seconds (~7 minutes)**

### What the team did

The same 5-agent team re-assembled with the v1 module files in context. The PI dispatched all three researchers at t=31.6s with identical tasks focused on identifying the most pleiotropic and well-characterised SNPs from the ~260 candidates.

After consensus synthesis and Reviewer confirmation, the PI selected the **five most pleiotropic SNPs**:

| rsid | Locus | Signal |
|------|-------|--------|
| rs964184 | ZNF259/APOA5 | Triglycerides and metabolic syndrome |
| rs12740374 | SORT1 | LDL cholesterol — protective allele |
| rs7310615 | SH2B3 | Blood pressure and inflammation |
| rs28601761 | TRIB1 | Hepatic fat and cardiometabolic risk |
| rs6547692 | GCKR | Triglyceride elevation and metabolic syndrome |

The Reviewer confirmed all five as well-documented in GWAS literature and accepted the weighting approach for inverse longevity correlation.

### Final output: v2

`variants.csv`: **48 variant rows** total — all 33 from v1 retained, plus 15 new rows (5 mvARD SNPs × 3 genotypes each) in a new **"mvARD"** category:

```csv
rs964184,C/C,0,neutral,"Normal lipid profile; baseline risk for cardiometabolic multimorbidity.",ZNF259,Multimorbidity & Longevity,mvARD
rs964184,C/G,-0.4,risk,"Heterozygous risk state; elevated triglycerides and increased risk of metabolic syndrome and myocardial infarction.",ZNF259,Multimorbidity & Longevity,mvARD
rs964184,G/G,-0.8,risk,"Homozygous risk state; significantly elevated triglycerides, high risk of metabolic syndrome and myocardial infarction, reducing longevity.",ZNF259,Multimorbidity & Longevity,mvARD
```

- `studies.csv`: 16 rows — all 11 from v1 plus 5 new entries linking mvARD SNPs to Dinh et al. 2025
- `MODULE.md` updated with new data source and v2 changelog
- Logo correctly **reused from v1** — the agent detected it existed and the module theme was unchanged

**No manual edits required.**

---

## Scenario 4 — Research team: `longevity_variants_2026` (create + edit + annotate)

This scenario demonstrates the complete end-to-end workflow: a Research Team creates a new module from a single preprint (v1 in ~284s), then iteratively edits it with a second article's findings (v2 in ~762s), registers the result as a local annotation source, and immediately uses it to annotate a real WGS sample alongside five other modules — all within a single session.

**Team composition:**
- PI: Gemini 3 Pro Preview
- Researcher 1: Gemini 3 Pro Preview
- Researcher 2: GPT-4.1 (OpenAI)
- Researcher 3: Claude Sonnet-4.5 (Anthropic)
- Reviewer: Gemini Flash Preview + Google Search

**Source papers:**
- Putter et al. (2025) — rare familial longevity variants (cGAS D452V + linkage loci). Uploaded as `Putter_longevity_variants_28.pdf`.
- Dinh et al. (2025), *GeroScience* (PMID 41405793) — multivariate GWAS of age-related disease multimorbidity (mvARD); 6 lead pleiotropic loci inversely correlated with extreme longevity. Uploaded as `Dink_ARDs_6.pdf`.

### Phase A: Create v1 (~284s)

**User input:**
```
Please create a module named longevity_variants 2026, based on the attached
```
(one PDF attached)

| Time | Actor | Action |
|------|-------|--------|
| 0.0s | System | Team assembled: PI + R1 (Gemini) + R2 (GPT-4.1) + R3 (Claude Sonnet-4.5) + Reviewer (Gemini Flash + Google Search) |
| 18.3s | PI | `delegate_task_to_member → researcher-1/2/3` simultaneously |
| 28.0s | R2 | `get_europepmc_articles` ×2 |
| 31.9s | R3 | `get_europepmc_articles` ×3 (batched) |
| 43.7s | R1 | `get_europepmc_articles` (first of 5 total EuropePMC calls) |
| 105.3s | R1 | Final `get_europepmc_articles` call completes |
| 150.5s | PI | All three researcher tasks complete |
| 189.5s | PI | `delegate_task_to_member → reviewer` (single QC cycle) |
| 232.0s | Reviewer | High-confidence verdict for cGAS rs200818241 with PMIDs 38155014 + 28592602 |
| 250.8s | PI | `write_spec_files` |
| 254.7s | PI | `validate_spec` — **VALID** |
| 263.0s | PI | `write_module_md` |
| 267.6s | PI | `generate_logo` |
| 283.9s | PI | **v1 complete** |

**v1 output:** 30 variant rows across 10 rsids in 6 categories (Inflammation / Cellular signaling / Nuclear function / Metabolism / Immunity / Mitochondrial function) covering CGAS, SH2D3A, NUP210L, SLC27A3 (×2 variants), CD1A, IBTK (×2 variants), RARS2 (×2 variants).

### Phase B: Edit to v2 (~762s)

**User input:**
```
Now, I want to add this other article's findings to the module
```
(second PDF attached; v1 still in editing slot)

| Time | Actor | Action |
|------|-------|--------|
| 21.9s | PI | `delegate_task_to_member → researcher-1/2/3` simultaneously |
| 31.8–78.2s | R1, R2, R3 | Parallel queries: EuropePMC ×12, Open Targets ×6, UniProt |
| 161.7s | PI | All 3 researcher tasks complete |
| 182.0s | PI | `delegate_task_to_member → researcher-2` (follow-up: UniProt lookup for NPC1, TFPI, BPTF) |
| 238.2s | PI | Follow-up complete |
| 243.1s | PI | **Reviewer cycle 1**: look up REF/ALT alleles for 6 new SNPs via Google Search |
| 416.6s | PI | **Reviewer cycle 2**: refined allele query — returns full SNP table with GRCh38 alleles |
| 550.0s | PI | **Reviewer cycle 3**: find PMID for Dinh et al. 2025 → returns **PMID 41405793** |
| 592.3s | PI | **Reviewer cycle 4**: final QC of complete draft CSV (all v1 + 18 new rows) |
| 681.2s | Reviewer | **ERRORS: None. WARNINGS: single-study provenance (acceptable; N > 400,000 multivariate GWAS). OK.** |
| 723.2s | PI | `write_spec_files` |
| 726.5s | PI | `validate_spec` — **VALID** |
| 743.8s | PI | `write_module_md` |
| 748.5s | PI | `generate_logo` |
| 761.9s | PI | **v2 complete** |

**The four reviewer cycles serve distinct purposes:**

1. **Cycles 1 & 2 — Allele lookup oracle.** The PI uses the Reviewer's Google Search access to obtain verified GRCh38 REF/ALT alleles for the 6 new SNPs. The first attempt returned partial results; the PI immediately re-delegated with a more specific query.
2. **Cycle 3 — PMID resolution.** The article was uploaded as a PDF without a machine-readable PMID; the Reviewer found PMID 41405793 via Google Search.
3. **Cycle 4 — Standard QC.** Final review of the complete draft CSV. The only warning was single-study provenance, which the Reviewer itself deemed acceptable given the study design (multivariate GWAS, N > 400,000, published in GeroScience).

**v2 output:** 48 variant rows total — 30 retained from v1 + 18 new rows (6 mvARD SNPs × 3 genotypes each) in a new **"Multimorbidity"** category:

| rsid | Gene | Risk allele logic |
|------|------|-------------------|
| rs1788785 | NPC1 | Alt T increases shared liability for CVD/metabolic multimorbidity |
| rs10931284 | TFPI | Alt T increases mvARD |
| rs6505080 | BPTF | Alt T increases mvARD |
| rs72887634 | GPD1L | Alt T increases mvARD |
| rs16959812 | LINC02512 | Alt A; novel locus with no prior univariate GWAS signal |
| rs9430037 | ABO | Alt C; ABO locus linked to inflammation and mvARD |

All 6 new SNPs carry negative weights (−0.2 het, −0.4 hom) because they increase age-related multimorbidity liability, which is inversely correlated with extreme longevity. `studies.csv` adds 6 rows for PMID 41405793.

### Post-creation: Register and annotate

After reviewing v2 in the editing slot, the user clicked **Register Module as source**. The module was written to `data/interim/registered_modules/` and a **Custom Modules** entry appeared in Module Sources alongside the HuggingFace catalogue. The user then switched to the **Annotation** tab where the `Longevity Variants 2026` card appeared alongside 5 curated modules from the remote source. With a WGS sample loaded, they clicked **Start Analysis** — closing the loop from AI-assisted creation to active annotation in a single session.

---

## Comparison across all four scenarios

| | Scenario 1 (Solo) | Scenario 2 (Team, new) | Scenario 3 (Team, edit) | Scenario 4 (Team, create+edit) |
|---|---|---|---|---|
| Module created | `familial_longevity` | `latest_longevity` | `latest_longevity` v2 | `longevity_variants_2026` |
| Mode | Single agent | Research team | Research team | Research team |
| Input | 1 PDF | 2 PDFs | 1 PDF + 1 CSV (~260 rows) | 1 PDF (v1) + 1 PDF (v2 edit) |
| Duration | ~107s | ~461s | ~418s | ~284s (v1) + ~762s (v2) |
| Researchers | — (self-researches) | 3 parallel (Gemini + GPT-4.1 + Claude) | 3 parallel (same) | 3 parallel (Gemini + GPT-4.1 + Claude Sonnet-4.5) |
| Reviewer cycles | — | 1 | 1 | 1 (v1) + 4 (v2) |
| Reviewer role | — | QC | QC | QC + lookup oracle (REF/ALT + PMID) |
| Variant rows produced | 12 (4 genes) | 33 (8 genes, 2 categories) | +15 new → 48 total (3 categories) | 30 (v1) + 18 new → 48 total (v2) |
| Database calls | 4 (OT, PMC ×2, BioRxiv) | 7+ per researcher | 8+ per researcher | PMC ×11 + OT ×6 (v1); PMC ×15 + OT ×6 + UniProt (v2) |
| Manual edits | None | None | None | None |
| Logo generated | Attempted (API error) | Yes (2025 genetics motif) | Skipped (existing reused) | Yes (v1); Yes (v2) |
| Post-creation step shown | — | Register implied | Register implied | **Register + Annotation tab** |

### Patterns

**Single agent is fast and good enough for focused sources.** If you have one well-defined paper and want a module in 2 minutes, solo mode is the right choice.

**Team mode provides depth and cross-model validation.** Using different LLMs for each Researcher (Gemini, GPT, Claude) introduces model diversity — each brings different strengths in literature interpretation, reducing systematic blind spots. The majority-vote consensus and Reviewer fact-checking act as built-in quality filters.

**Iterative editing works cleanly.** Scenarios 3 and 4 demonstrate that the system can extend an existing module incrementally, preserving all prior content and reusing assets (logo) when appropriate. This mirrors how real research curation works.

**The Reviewer is more than a QC gate.** In Scenario 4 v2, the Reviewer was called four times — twice as an allele lookup oracle (Google Search for GRCh38 REF/ALT), once for PMID resolution, and once for final QC. This dual role avoids re-spinning full researcher tasks for simple factual lookups.

---

## Example: AI-generated module from a prompt (no paper)

You don't need a PDF. A text description is enough for well-studied variants:

**Prompt:**
```
Create a module for MTHFR methylation variants. Include rs1801133 (C677T) and rs1801131 (A1298C). Focus on homocysteine metabolism and cardiovascular risk.
```

**Resulting `module_spec.yaml`:**
```yaml
schema_version: "1.0"

module:
  name: mthfr_methylation
  version: 1
  title: "MTHFR Methylation Variants"
  description: "MTHFR variants affecting homocysteine metabolism and cardiovascular risk."
  report_title: "Methylation & Cardiovascular Risk"
  icon: dna
  color: "#21ba45"

defaults:
  curator: ai-module-creator
  method: literature-review
  priority: medium

genome_build: GRCh38
```

**Resulting `variants.csv`:**
```csv
rsid,genotype,weight,state,conclusion,gene,phenotype,category
rs1801133,C/C,0,neutral,"Typical MTHFR C677T activity; normal homocysteine metabolism.",MTHFR,Homocysteine Metabolism,Methylation
rs1801133,C/T,-0.6,risk,"MTHFR C677T heterozygote; ~35% reduced enzyme activity; mildly elevated homocysteine risk.",MTHFR,Homocysteine Metabolism,Methylation
rs1801133,T/T,-1.1,risk,"MTHFR C677T homozygote; ~70% reduced enzyme activity; significantly elevated cardiovascular risk.",MTHFR,Homocysteine Metabolism,Methylation
rs1801131,A/A,0,neutral,"Typical MTHFR A1298C activity.",MTHFR,Homocysteine Metabolism,Methylation
rs1801131,A/C,-0.4,risk,"MTHFR A1298C heterozygote; mildly reduced enzyme activity.",MTHFR,Homocysteine Metabolism,Methylation
rs1801131,C/C,-0.8,risk,"MTHFR A1298C homozygote; compound effect when combined with C677T.",MTHFR,Homocysteine Metabolism,Methylation
```

---

## Agent flow diagrams

### Simple mode

```
User types prompt
      │
[optional] Attach PDF/CSV
      │
Solo Agent (Gemini Pro)
  ├── BioContext MCP (variant lookup, EuropePMC, Open Targets, Ensembl, BioRxiv)
  ├── write_spec_files
  ├── validate_spec ──→ [errors?] ──→ self-correct (up to 10 iterations)
  ├── write_module_md
  └── generate_logo
      │
Module in Editing Slot
      │
User: Register / Download / Iterate via chat
```

### Research team mode

```
User types prompt + optional attachments (PDF / CSV / MD / TXT)
      │
      ▼
PI (Gemini Pro) receives task + [existing module if in editing slot]
      │
      ├─────────────────────────────────────────────────────────────┐
      │  NEW MODULE path                                            │
      │    PI delegates identical research task in parallel:        │
      │                                                             │
      │    Researcher 1      Researcher 2      Researcher 3         │
      │   (Gemini Pro)      (GPT-4.1,          (Claude,             │
      │                      optional)          optional)           │
      │         │                 │                  │              │
      │         ▼                 ▼                  ▼              │
      │    EuropePMC        Open Targets        UniProt /           │
      │    literature       variant–disease     BioRxiv             │
      │    searches         associations        protein info        │
      │         │                 │                  │              │
      │         └─────────────────┴──────────────────┘              │
      │                           │                                 │
      │                           ▼                                 │
      │              PI synthesises consensus                       │
      │          (majority vote; median weights)                    │
      └─────────────────────────────────────────────────────────────┘
      │
      ├─────────────────────────────────────────────────────────────┐
      │  EDIT path  (module already in editing slot)                │
      │    PI reads existing module_spec.yaml + variants.csv        │
      │    PI delegates targeted research on new article only       │
      │    PI may follow-up with individual researchers             │
      │    PI merges new rows into existing CSV                     │
      └─────────────────────────────────────────────────────────────┘
      │
      ▼
PI → Reviewer (Gemini Flash + Google Search)
      │
      │  Reviewer may be called multiple times for:
      │    1. Lookup oracle  — REF/ALT alleles for new SNPs
      │    2. PMID lookup    — find correct citation for uploaded PDF
      │    3. QC review      — provenance, weights, genome build
      │
      ├── ERRORS   → PI corrects and re-submits to Reviewer
      ├── WARNINGS → PI addresses (may accept if evidence is strong)
      └── OK ──────────────────────────────────────────────────────┐
                                                                   │
                                                                   ▼
                          write_spec_files → validate_spec
                                 │
                          write_module_md → generate_logo
                                 │
                          ┌──────▼─────────────────────────┐
                          │     Module in Editing Slot     │
                          │  (version auto-incremented     │
                          │   on each edit)                │
                          └──────┬─────────────────────────┘
                                 │
              ┌──────────────────┼──────────────────────┐
              ▼                  ▼                       ▼
       Register as         Download .zip           Iterate
       annotation          (spec files            (send new
       source              for sharing)            message
              │                                    with new
              ▼                                    article)
  Module Sources →
  Custom Modules list
              │
              ▼
  Annotation tab →
  module card in selection grid
              │
              ▼
  Start Analysis → module participates in VCF annotation run
```

---

## Limitations

- **Max 5 file attachments** per message. Supported formats: PDF, CSV, Markdown, plain text. No DOCX or HTML.
- **BioContext MCP budget**: each Researcher is limited to 9 tool calls to prevent context overflow. Very large variant sets may be truncated.
- **No human-in-the-loop** between PI→Researcher→Reviewer phases. If the PI misinterprets the task, use a follow-up chat message to correct it.
- **Gemini key required.** OpenAI and Anthropic keys add Researchers but are optional.
- **GRCh38 only** — the platform does not support GRCh37 or other genome builds.
- **Only SNPs/indels** — structural and copy-number variants are not supported.
- **No persistent audit trail** — intermediate researcher outputs are visible in the chat session only and are not saved across page reloads. Run logs (`.log` files) are saved with the module.
- **Logo generation** requires Gemini API; silently skipped if the API call fails.

---

## Interpreting the logs

The `.log` files are machine-generated by the `RunLog` class in `module_creator.py`. Each line has the format:

```
[ elapsed_s]  >> tool_name       ← tool call started
[ elapsed_s]  DONE tool_name ✓   ← tool call completed
[ elapsed_s] [agno_run_log.team] message  ← internal Agno framework message
```

For team runs, tool calls from member agents appear as:
```
Researcher N: get_europepmc_articles    ← member tool call
PI → reviewer                           ← delegation
PI: write_spec_files                    ← PI tool call
```

The logs preserve intermediate outputs in full (up to 2000 chars per tool call), including raw JSON from BioContext KB and CSV drafts passed to the Reviewer.

---

## Further reading

- [AI_MODULE_CREATION.md](AI_MODULE_CREATION.md) — DSL spec, compiler internals, registry API, Agno agent architecture
- [HF_MODULES.md](HF_MODULES.md) — module discovery from HuggingFace and other remote sources
- [ARCHITECTURE.md](ARCHITECTURE.md) — overall pipeline and data flow
