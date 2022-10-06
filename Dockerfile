FROM ubuntu

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y build-essential
RUN apt-get -y install bison gawk
RUN apt-get -y install wget

RUN mkdir /lfs
ENV LFS=/lfs

RUN mkdir -v $LFS/sources
RUN chmod -v a+wt $LFS/sources
RUN wget https://www.linuxfromscratch.org/lfs/view/stable/wget-list-sysv -O $LFS/sources/wget-list-sysv
RUN wget --input-file=$LFS/sources/wget-list-sysv --continue --directory-prefix=$LFS/sources
