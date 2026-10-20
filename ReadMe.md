ReadMe

How to download HLA-HD:
>HLA-HD (HLA typing from High-quality Dictionary) can accurately determine HLA alleles with 6-digit precision from NGS data (fastq format). RNA-Seq data can also be applied.

>Note that HLA-HD is freely available for academic purposes, non-commercial research purposes and six months limited term evaluation purpose to enter into commercial licenses. Kyoto University reserves its right to modify terms and restrictions at any time.

To download the tool, you must submit a request through here: https://w3.genome.med.kyoto-u.ac.jp/HLA-HD/kyoto-hlahd-download-request-20250310/

You'll be emailed access afterwards. We're working with the newest version: 1.7.1

________________________________________________________________________________________________

I've sent over an automated Slurm batch pipeline [run_hlahd_cram.sh](https://github.com/jadealicee/HLAHD/blob/main/run_hlahd_cram.sh) for performing high-resolution HLA typing from indexed CRAM files using HLA-HD (v1.7.1) and the IPD-IMGT/HLA v3.15.0 reference database.

Setting up your environment (with the yaml file):
```
conda env create -f environment.yaml
conda activate hlahd
```
________________________________________________________________________________________________

The custom-compiled execution binaries (hla_est, pick_up_allele, sam_to_fastq_reverse, etc.) are pre-compiled and placed inside the /bin/ directory of hla-hd. run_hlahd_cram.sh should append the /bin/ directory to your $PATH. 

________________________________________________________________________________________________


~~Due to legacy server archiving changes on the IPD-IMGT/HLA FTP, the pre-indexed IPD-IMGT/HLA 3.15.0 reference files can be provided from me as a compressed bundle. I've been unable to locate them again on the online archive, so I've zipped up my dictionary and can send it over whenever required (1.8gb zipped, 30gb unzipped).~~ If you can find the ref files yourself, that may be the easiest method, but I've some digging on both their archive and their github and have not been able to locate them. It's the hla_nuc.fasta and the hla_gen.fasta from the 3.15 version which is needed.

I  have uploaded the raw files to this repository as a zipped file called [IMGTHLA-3150.tar.gz](https://github.com/jadealicee/HLAHD/blob/main/IMGTHLA-3150.tar.gz). Will take some time to build the dictionary. Any issues and I can send over the pre-indexed version instead.

using the raws, the dictionary can be made with this:
```
tar -xzvf IMGTHLA-3150.tar.gz
python3 bin/hlahd_update.py \
   -g IMGTHLA-3150/hla_gen.fasta \
   -c IMGTHLA-3150/hla_nuc.fasta \
   -a IMGTHLA-3150/alignments/ \
   -o dictionary315
```
________________________________________________________________________________________________


The script is written for slurm. Currently is used for: MHC region extraction (chr6:28477797-33448354), multithreaded sorting, conversion to paired FASTQ files, HLA-HD typing, temporary file cleanup, and execution metric logging

example of a submission:
```
sbatch \
    --cpus-per-task=10 \
    --mem=60G \
    --time=02:00:00 \
    run_hlahd_cram.sh \
    /path/to/sample_input.cram \
    /path/to/genome_reference.fasta \
    /path/to/output_directory \
    SAMPLE_ID
```
ensure cram files have matching crai in the same directory
-t 10 for threads allows for much faster processing
-m 55 filters out reads < 55bp to reduce ambiguous mapping

________________________________________________________________________________________________


Upon completion, output files will be created in your designated ${OUT_DIR}
${OUT_DIR}/${SAMPLE_ID}/${SAMPLE_ID}_final.result.txt: The final 4-digit and 6-digit HLA locus calls.
metrics/${SAMPLE_ID}_performance.log: Contains total execution wall-clock time, peak RAM use (via Slurm cgroups/sstat), and peak temporary disk usage.

________________________________________________________________________________________________


If you need any clarification, please don't hesitate to reach out. My name is Jade and my email is gregoryja2@cardiff.ac.uk
All the best!
