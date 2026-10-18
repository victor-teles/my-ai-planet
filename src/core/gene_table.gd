class_name GeneTable
extends RefCounted
## One species' genes, in genome order. A genome is two allele bytes (0-255) per gene.
## Additive genes show as the average of the copies. A recessive gene shows only when both
## copies carry it, so it can skip a generation.

var genes: Array[String] = []
var info: Dictionary = {}
## The genes a pool chart follows, in draw order.
var tracked: Array[String] = []
## Founder rows. Human rows are [pigment, hair, narrow-eye share]. Empty when founders are
## only a spread around the middle.
var ancestries: Array[Array] = []
var mutation_chance: float = 0.015 ## per copy: a small shift
var big_mutation_chance: float = 0.002 ## per copy: a brand new allele
## gene -> {"mode": "above"|"below", "at": int}. "above" carries when value >= at;
## "below" carries when value < at. The trait shows only with two carrying copies.
var recessive: Dictionary = {}
## gene -> founder draw read by Genetics.founder. Genes with no rule keep the mid roll.
var founder_rules: Dictionary = {}


func index_of(gene: String) -> int:
	return genes.find(gene)


func carries(gene: String, value: int) -> bool:
	if not recessive.has(gene):
		return false
	var rule: Dictionary = recessive[gene]
	var at := int(rule["at"])
	if String(rule["mode"]) == "below":
		return value < at
	return value >= at


func allele_count(genome: PackedByteArray, gene: String) -> int:
	var index := index_of(gene)
	if index < 0:
		return 0
	var g := index * 2
	return int(carries(gene, genome[g])) + int(carries(gene, genome[g + 1]))


## True when both copies carry this recessive allele.
func shows(genome: PackedByteArray, gene: String) -> bool:
	return allele_count(genome, gene) == 2
