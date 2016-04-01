library(phyloseq)
library(Hmisc)
library(plyr)
library(reshape2)
library(igraph)
library(fdrtool)

### input args: 1. phyloseq RDS object; 2. the last column that is a factor; 
args<-commandArgs(TRUE)
input_path<-unlist(strsplit(as.character(args[1]), "/", fixed=T))
full_name<-input_path[length(input_path)]
input_name<-strsplit(as.character(full_name), ".", fixed=T)

# phyloseq RDS object 
physeq<-readRDS(args[1])
print(physeq)

# at genus level:
physeq<-tax_glom(physeq, "genus")
physeq<-subset_taxa(physeq, domain!="Archaea" & domain!="unclassified_Root")

otu<-data.frame(otu_table(physeq))
si<-data.frame(sample_data(physeq))
tax<-data.frame(tax_table(physeq))
row.names(otu)<-tax$genus
totu<-data.frame(t(otu))

# merging sample information and otu table:
dataset<-merge(si, totu, by.x="SAMPLES", by.y="row.names")
print(dim(dataset))

# co-occurrence by Foaming.Status
treatments<-as.vector(unique(dataset$Foaming.Status))
final_results<-data.frame()
for(i in 1:length(treatments)){
	#subset the data for a particular treatment
	temp<-subset(dataset, Foaming.Status==treatments[i])
	# making an object that has all the results in it (both rho and P values)
	results<-rcorr(as.matrix(temp[,-c(1:args[2])]),type="spearman")
	#make two seperate objects for p-value and correlation coefficients
	rhos<-results$r
	ps<-results$P
	# going to melt these objects to 'long form' where the first two columns make up the pairs of OTUs, I am also removing NA's as they are self-comparisons, not enough data, other bad stuff
	ps_melt<-na.omit(melt(ps))
	#creating a qvalue (adjusted pvalue) based on FDR
	ps_melt$qval<-fdrtool(ps_melt$value, statistic="pvalue", plot=F,verbose=F)$qval
	#making column names more relevant
	names(ps_melt)[3]<-"pval"
	# if you are of the opinion that it is a good idea to subset your network based on adjusted P-values (qval in this case), you can then subset here
	ps_sub<-subset(ps_melt, qval < 0.05)
	# now melting the rhos, note the similarity between ps_melt and rhos_melt
	rhos_melt<-na.omit(melt(rhos))
	names(rhos_melt)[3]<-"rho"
	#merging together and remove negative rhos
	merged<-merge(ps_sub,subset(rhos_melt, rho > 0),by=c("Var1","Var2"))
	merged$trt<-treatments[i]
	final_results<-rbind(final_results, merged)
	print(paste("finished ",treatments[i],sep=""))
}
# you can write the results out into a flat tab delimited table
write.table(final_results, paste(unlist(input_name)[1], "_final_results.txt", sep=""), sep="\t", row.names=F, quote=F)

# now we can calculate stats for the network
final_stats<-data.frame()
for(i in 1:length(unique(final_results$trt))){
	temp<-subset(final_results, trt==as.vector(unique(final_results$trt))[i])
	temp.graph<-(graph.edgelist(as.matrix(temp[,c(1,2)]),directed=FALSE))
	E(temp.graph)$weight<-temp$rho
	temp.graph<-simplify(temp.graph)
	stats<-data.frame(row.names((as.matrix(igraph::degree(temp.graph,normalized=TRUE)))),(as.matrix(igraph::degree(temp.graph,normalized=TRUE))),(as.matrix(igraph::betweenness(temp.graph))))
	names(stats)<-c("otus","norm_degree","betweenness")
	stats$trt<-as.vector(unique(final_results$trt))[i]
	stats$clustering_coeff<-igraph::transitivity(temp.graph,type="global")
	stats$clustering_coeff_rand<-igraph::transitivity(igraph::erdos.renyi.game(length(V(temp.graph)),length(E(temp.graph)),type="gnm"))
	stats$cluster_ratio<-stats$clustering_coeff/stats$clustering_coeff_rand
	final_stats<-rbind(final_stats,stats)
	print(paste("finished ",as.vector(unique(final_results$trt))[i],sep=""))
}
# you can write the results out into a flat tab delimited table
write.table(final_stats, paste(unlist(input_name)[1], "_final_stats.txt", sep=""), sep="\t", row.names=F, quote=F)

#meta<-read.delim("foaming_status_cc/meta_w_genus_information.txt", sep="\t", header=T)
meta<-read.delim(args[3], sep="\t", header=T)

## separte measurement:measurement, bacteria:bacteria interactions
temp<-merge(final_results, meta[, c("genus", "domain")], by.x="Var1", by.y="genus")
temp<-merge(temp, meta[, c("genus", "domain")], by.x="Var2", by.y="genus")
## bacteria to bacteria
bac.bac<-subset(temp, domain.x=="Bacteria" & domain.y=="Bacteria")[, 1:6]
## bacteria to measurements
bac.m<-rbind(subset(temp, domain.x=="Bacteria" & domain.y=="measurements")[, 1:6], subset(temp, domain.y=="Bacteria" & domain.x=="measurements")[, 1:6])

write.table(bac.bac, paste(unlist(input_name)[1], "_final_results_bac_bac.txt", sep=""), sep="\t", row.names=F, quote=F)
write.table(bac.m, paste(unlist(input_name)[1], "_final_results_bac_measurements.txt", sep=""), sep="\t", row.names=F, quote=F)
