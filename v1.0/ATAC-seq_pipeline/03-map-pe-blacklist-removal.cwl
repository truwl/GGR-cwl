#!/usr/bin/env cwl-runner
class: Workflow
cwlVersion: v1.0
doc: 'ATAC-seq 03 mapping - reads: PE - blacklist removal'
requirements:
 - class: ScatterFeatureRequirement
 - class: SubworkflowFeatureRequirement
 - class: StepInputExpressionRequirement
 - class: InlineJavascriptRequirement
inputs:
   input_fastq_read1_files:
     doc: Input fastq files for paired_read1
     type: File[]
   input_fastq_read2_files:
     doc: Input fastq files for paired_read2
     type: File[]
   ENCODE_blacklist_bedfile:
     doc: Bedfile containing ENCODE consensus blacklist regions to be excluded.
     type: File
   genome_sizes_file:
     doc: Genome sizes tab-delimited file (used in samtools)
     type: File
   genome_ref_first_index_file:
     doc: Bowtie first index files for reference genome (e.g. *1.ebwt). The rest of the files should be in the same folder.
     type: File
     secondaryFiles:
       - ^^.2.ebwt
       - ^^.3.ebwt
       - ^^.4.ebwt
       - ^^.rev.1.ebwt
       - ^^.rev.2.ebwt
   picard_jar_path:
     default: /usr/picard/picard.jar
     doc: Picard Java jar file
     type: string
   picard_java_opts:
     doc: JVM arguments should be a quoted, space separated list (e.g. "-Xms128m -Xmx512m")
     type: string?
   nthreads:
     default: 1
     type: int
steps:
   extract_basename_1:
     run: ../utils/extract-basename.cwl
     scatter: input_file
     in:
       input_file: input_fastq_read1_files
     out:
     - output_basename
   extract_basename_2:
     run: ../utils/remove-extension.cwl
     scatter: file_path
     in:
       file_path: extract_basename_1/output_basename
     out:
     - output_path
   bowtie-pe:
     run: ../map/bowtie-pe.cwl
     scatterMethod: dotproduct
     scatter:
     - input_fastq_read1_file
     - input_fastq_read2_file
     - output_filename
     in:
       input_fastq_read1_file: input_fastq_read1_files
       input_fastq_read2_file: input_fastq_read2_files
       output_filename: extract_basename_2/output_path
       v:
         valueFrom: ${return 2}
       X:
         valueFrom: ${return 2000}
       genome_ref_first_index_file: genome_ref_first_index_file
       nthreads: nthreads
     out:
     - output_aligned_file
     - output_bowtie_log
   sam2bam:
     run: ../map/samtools2bam.cwl
     scatter: input_file
     in:
       nthreads: nthreads
       input_file: bowtie-pe/output_aligned_file
     out:
     - bam_file
   sort_bams:
     run: ../map/samtools-sort.cwl
     scatter: input_file
     in:
       nthreads: nthreads
       input_file: sam2bam/bam_file
     out:
     - sorted_file
   index_bams:
     run: ../map/samtools-index.cwl
     scatter: input_file
     in:
       input_file: sort_bams/sorted_file
     out:
     - indexed_file
   filter-unmapped:
     run: ../map/samtools-filter-unmapped.cwl
     scatterMethod: dotproduct
     scatter:
     - input_file
     - output_filename
     in:
       output_filename: extract_basename_2/output_path
       input_file: sort_bams/sorted_file
     out:
     - filtered_file
   filtered2sorted:
     run: ../map/samtools-sort.cwl
     in:
       nthreads: nthreads
       input_file: filter-unmapped/filtered_file
     scatter:
     - input_file
     out:
     - sorted_file
   index_filtered_bam:
     run: ../map/samtools-index.cwl
     scatter: input_file
     in:
       input_file: filtered2sorted/sorted_file
     out:
     - indexed_file
   preseq-c-curve:
     run: ../map/preseq-c_curve.cwl
     scatterMethod: dotproduct
     scatter:
     - input_sorted_file
     - output_file_basename
     in:
       input_sorted_file: filtered2sorted/sorted_file
       output_file_basename: extract_basename_2/output_path
       pe:
         valueFrom: ${return true}
     out:
     - output_file
   execute_pcr_bottleneck_coef:
     in:
       input_bam_files: filtered2sorted/sorted_file
       genome_sizes: genome_sizes_file
       input_output_filenames: extract_basename_2/output_path
     run: ../map/pcr-bottleneck-coef.cwl
     out:
     - pbc_file
   remove_encode_blacklist:
     run: ../map/bedtools-intersect.cwl
     scatterMethod: dotproduct
     scatter:
     - a
     - output_basename_file
     in:
       a: filtered2sorted/sorted_file
       b: ENCODE_blacklist_bedfile
       output_basename_file: extract_basename_2/output_path
       v:
         valueFrom: ${return true}
     out:
     - file_wo_blacklist_regions
   masked_file_basename:
     run: ../utils/extract-basename.cwl
     scatter: input_file
     in:
       input_file: remove_encode_blacklist/file_wo_blacklist_regions
     out:
     - output_basename
   sort_masked_bams:
     run: ../map/samtools-sort.cwl
     scatter:
     - input_file
     in:
       nthreads: nthreads
       input_file: remove_encode_blacklist/file_wo_blacklist_regions
     out:
     - sorted_file
   index_masked_bams:
     run: ../map/samtools-index.cwl
     scatter:
     - input_file
     in:
       input_file: sort_masked_bams/sorted_file
     out:
     - indexed_file
   mark_duplicates:
     run: ../map/picard-MarkDuplicates.cwl
     scatterMethod: dotproduct
     scatter:
     - input_file
     - output_filename
     in:
       input_file: index_masked_bams/indexed_file
       java_opts: picard_java_opts
       picard_jar_path: picard_jar_path
       output_filename: masked_file_basename/output_basename
       output_suffix:
         valueFrom: bam
     out:
     - output_metrics_file
     - output_dedup_bam_file
   sort_dups_marked_bams:
     run: ../map/samtools-sort.cwl
     scatter:
     - input_file
     in:
       nthreads: nthreads
       input_file: mark_duplicates/output_dedup_bam_file
       suffix:
         valueFrom: .dups_marked.bam
     out:
     - sorted_file
   index_dups_marked_bams:
     run: ../map/samtools-index.cwl
     scatter:
     - input_file
     in:
       input_file: sort_dups_marked_bams/sorted_file
     out:
     - indexed_file
   remove_duplicates:
     run: ../map/samtools-view.cwl
     scatter:
     - input_file
     in:
       input_file: index_dups_marked_bams/indexed_file
       F:
         valueFrom: ${return 1024}
       suffix:
         valueFrom: .dedup.bam
       b:
         valueFrom: ${return true}
       outfile_name:
         valueFrom: ${return inputs.input_file.basename.replace('dups_marked', 'dedup')}
     out:
     - outfile
   sort_dedup_bams:
     run: ../map/samtools-sort.cwl
     scatter:
     - input_file
     in:
       nthreads: nthreads
       input_file: remove_duplicates/outfile
     out:
     - sorted_file
   index_dedup_bams:
     run: ../map/samtools-index.cwl
     scatter:
     - input_file
     in:
       input_file: sort_dedup_bams/sorted_file
     out:
     - indexed_file
   mapped_reads_count:
     run: ../map/bowtie-log-read-count.cwl
     scatter: bowtie_log
     in:
       bowtie_log: bowtie-pe/output_bowtie_log
     out:
     - output
   percent_uniq_reads:
     run: ../map/preseq-percent-uniq-reads.cwl
     scatter: preseq_c_curve_outfile
     in:
       preseq_c_curve_outfile: preseq-c-curve/output_file
     out:
     - output
   mapped_filtered_reads_count:
     run: ../peak_calling/samtools-extract-number-mapped-reads.cwl
     scatter: input_bam_file
     in:
       output_suffix:
         valueFrom: .mapped_and_filtered.read_count.txt
       input_bam_file: sort_dedup_bams/sorted_file
     out:
     - output_read_count
   bam_idxstats:
     run: ../map/samtools-idxstats.cwl
     scatter: bam
     in:
       bam: index_bams/indexed_file
     out:
     - idxstats_file
   percent_mitochondrial_reads:
     run: ../utils/idxstats-percentage-of-reads-in-chrom.cwl
     scatter: idxstats
     in:
       idxstats: bam_idxstats/idxstats_file
       chrom:
         valueFrom: chrM
       output_filename:
         valueFrom: ${return inputs.idxstats.basename.replace(/^.*[\\\/]/, '').replace(/\.[^/.]+$/, '').replace(/\.[^/.]+$/, '').replace(/\.[^/.]+$/, '.mitochondrial_percentage.txt')}
     out:
     - percent_map
outputs:
   output_pbc_files:
     doc: PCR Bottleneck Coeficient files.
     type: File[]
     outputSource: execute_pcr_bottleneck_coef/pbc_file
   output_read_count_mapped:
     doc: Read counts of the mapped BAM files
     type: File[]
     outputSource: mapped_reads_count/output
   output_data_sorted_dedup_bam_files:
     doc: BAM files without duplicate reads.
     type: File[]
     outputSource: index_dedup_bams/indexed_file
   output_data_sorted_dups_marked_bam_files:
     doc: BAM files with marked duplicate reads.
     type: File[]
     outputSource: index_dups_marked_bams/indexed_file
   output_picard_mark_duplicates_files:
     doc: Picard MarkDuplicates metrics files.
     type: File[]
     outputSource: mark_duplicates/output_metrics_file
   output_read_count_mapped_filtered:
     doc: Read counts of the mapped and filtered BAM files
     type: File[]
     outputSource: mapped_filtered_reads_count/output_read_count
   output_percentage_uniq_reads:
     doc: Percentage of uniq reads from preseq c_curve output
     type: File[]
     outputSource: percent_uniq_reads/output
   output_bowtie_log:
     doc: Bowtie log file.
     type: File[]
     outputSource: bowtie-pe/output_bowtie_log
   output_preseq_c_curve_files:
     doc: Preseq c_curve output files.
     type: File[]
     outputSource: preseq-c-curve/output_file
   output_percent_mitochondrial_reads:
     doc: Percentage of mitochondrial reads.
     type: File[]
     outputSource: percent_mitochondrial_reads/percent_map