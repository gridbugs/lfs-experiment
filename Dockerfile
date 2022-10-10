FROM ubuntu

RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    build-essential \
    file \
    texinfo \
    bison \
    gawk \
    wget \
    vim \
    tmux \
    git

# make working directory
ENV LFS=/lfs
RUN mkdir $LFS
RUN mkdir -v $LFS/sources
RUN chmod -v a+wt $LFS/sources

# download sources
COPY wget-list-sysv $LFS/sources
RUN wget --input-file=$LFS/sources/wget-list-sysv --directory-prefix=$LFS/sources

# set up directory hierarchy
RUN bash -c "mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin} $LFS/lib64"
RUN for i in bin lib sbin; do ln -sv usr/$i $LFS/$i; done
RUN mkdir -pv $LFS/tools

# add lfs user
RUN groupadd lfs
RUN useradd -s /bin/bash -g lfs -m -k /dev/null lfs
RUN chown -R -v lfs $LFS
USER lfs
WORKDIR $LFS
ENV HOME=/home/lfs
COPY bash_profile $HOME/.bash_profile
COPY bashrc $HOME/.bashrc
ENV LC_ALL=POSIX
ENV LFS_TGT=x86_64-lfs-linux-gnu
ENV PATH=$LFS/tools/bin:/usr/bin
ENV CONFIG_SITE=$LFS/usr/share/config.site
ENV MAKEFLAGS='-j'

# Binutils-2.39 - Pass 1
RUN cd $LFS/sources && tar xvf binutils-2.39.tar.xz
RUN cd $LFS/sources/binutils-2.39 && mkdir -v build && cd build && ../configure --prefix=$LFS/tools \
    --with-sysroot=$LFS \
    --target=$LFS_TGT   \
    --disable-nls       \
    --enable-gprofng=no \
    --disable-werror
RUN cd $LFS/sources/binutils-2.39/build && make
RUN cd $LFS/sources/binutils-2.39/build && make install

# GCC-12.2.0 - Pass 1
RUN cd $LFS/sources && tar xvf gcc-12.2.0.tar.xz
RUN cd $LFS/sources/gcc-12.2.0 && tar -xf ../mpfr-4.1.0.tar.xz && mv -v mpfr-4.1.0 mpfr
RUN cd $LFS/sources/gcc-12.2.0 && tar -xf ../gmp-6.2.1.tar.xz && mv -v gmp-6.2.1 gmp
RUN cd $LFS/sources/gcc-12.2.0 && tar -xf ../mpc-1.2.1.tar.gz && mv -v mpc-1.2.1 mpc
RUN cd $LFS/sources/gcc-12.2.0 && sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
RUN cd $LFS/sources/gcc-12.2.0 && mkdir -v build && cd build && ../configure \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.36 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-decimal-float   \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++
RUN cd $LFS/sources/gcc-12.2.0/build && make
RUN cd $LFS/sources/gcc-12.2.0/build && make install
RUN cd $LFS/sources/gcc-12.2.0 && bash -c "cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/install-tools/include/limits.h"

