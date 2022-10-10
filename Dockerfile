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
    git \
    python3

# make working directory
ENV LFS=/lfs
RUN mkdir $LFS \
    && mkdir -v $LFS/sources \
    && chmod -v a+wt $LFS/sources

# download sources
COPY wget-list-sysv $LFS/sources
RUN wget --input-file=$LFS/sources/wget-list-sysv --directory-prefix=$LFS/sources

# set up directory hierarchy
RUN bash -c "mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin} $LFS/lib64" \
    && for i in bin lib sbin; do ln -sv usr/$i $LFS/$i; done \
    && mkdir -pv $LFS/tools

# add lfs user
RUN groupadd lfs \
    &&  useradd -s /bin/bash -g lfs -m -k /dev/null lfs \
    &&  chown -R -v lfs $LFS
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
    --disable-werror \
    && make && make install

# GCC-12.2.0 - Pass 1
RUN cd $LFS/sources && tar xvf gcc-12.2.0.tar.xz \
    && cd $LFS/sources/gcc-12.2.0 && tar -xf ../mpfr-4.1.0.tar.xz && mv -v mpfr-4.1.0 mpfr \
    && cd $LFS/sources/gcc-12.2.0 && tar -xf ../gmp-6.2.1.tar.xz && mv -v gmp-6.2.1 gmp \
    && cd $LFS/sources/gcc-12.2.0 && tar -xf ../mpc-1.2.1.tar.gz && mv -v mpc-1.2.1 mpc \
    && cd $LFS/sources/gcc-12.2.0 && sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
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
    --enable-languages=c,c++ \
    && cd $LFS/sources/gcc-12.2.0/build && make \
    && cd $LFS/sources/gcc-12.2.0/build && make install \
    && cd $LFS/sources/gcc-12.2.0 && bash -c "cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/install-tools/include/limits.h"

# Linux-5.19.2 API Headers
RUN cd $LFS/sources && tar xvf linux-5.19.2.tar.xz
RUN cd $LFS/sources/linux-5.19.2 && make mrproper \
    && cd $LFS/sources/linux-5.19.2 && make headers \
    && cd $LFS/sources/linux-5.19.2 && find usr/include -type f ! -name '*.h' -delete \
    && cd $LFS/sources/linux-5.19.2 && cp -rv usr/include $LFS/usr

# Glibc-2.36
RUN ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
RUN ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
RUN cd $LFS/sources && tar xvf glibc-2.36.tar.xz
RUN cd $LFS/sources/glibc-2.36 && patch -Np1 -i ../glibc-2.36-fhs-1.patch
RUN cd $LFS/sources/glibc-2.36 && mkdir -v build && cd build && echo "rootsbindir=/usr/sbin" > configparms && ../configure \
    --prefix=/usr                      \
    --host=$LFS_TGT                    \
    --build=$(../scripts/config.guess) \
    --enable-kernel=3.2                \
    --with-headers=$LFS/usr/include    \
    libc_cv_slibdir=/usr/lib \
    && make \
    && make DESTDIR=$LFS install \
    && sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd \
    && $LFS/tools/libexec/gcc/$LFS_TGT/12.2.0/install-tools/mkheaders \
    && echo 'int main(){}' | gcc -xc - && readelf -l a.out | grep ld-linux && rm -v a.out

# Libstdc++ from GCC-12.2.0
RUN cd $LFS/sources/gcc-12.2.0 && mkdir -v build-libstdc++ && cd build-libstdc++ && ../libstdc++-v3/configure           \
    --host=$LFS_TGT                 \
    --build=$(../config.guess)      \
    --prefix=/usr                   \
    --disable-multilib              \
    --disable-nls                   \
    --disable-libstdcxx-pch         \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/12.2.0 \
    && make && make DESTDIR=$LFS install \
    && bash -c "rm -v $LFS/usr/lib/lib{stdc++,stdc++fs,supc++}.la"

# M4-1.4.19
RUN cd $LFS/sources && tar xvf m4-1.4.19.tar.xz
RUN cd $LFS/sources/m4-1.4.19 && ./configure --prefix=/usr   \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess) \
    && make && make DESTDIR=$LFS install

# Ncurses-6.3
RUN cd $LFS/sources && tar xvf ncurses-6.3.tar.gz
RUN cd $LFS/sources/ncurses-6.3 && sed -i s/mawk// configure
RUN cd $LFS/sources/ncurses-6.3 && mkdir build && cd build && ../configure && make -C include && make -C progs tic
RUN cd $LFS/sources/ncurses-6.3 && ./configure --prefix=/usr                \
    --host=$LFS_TGT              \
    --build=$(./config.guess)    \
    --mandir=/usr/share/man      \
    --with-manpage-format=normal \
    --with-shared                \
    --without-normal             \
    --with-cxx-shared            \
    --without-debug              \
    --without-ada                \
    --disable-stripping          \
    --enable-widec \
    && make \
    && make DESTDIR=$LFS TIC_PATH=$(pwd)/build/progs/tic install \
    && echo "INPUT(-lncursesw)" > $LFS/usr/lib/libncurses.so

# Bash-5.1.16
RUN cd $LFS/sources && tar xvf bash-5.1.16.tar.gz
RUN cd $LFS/sources/bash-5.1.16 && ./configure --prefix=/usr \
    --build=$(support/config.guess) \
    --host=$LFS_TGT                 \
    --without-bash-malloc \
    && make && make DESTDIR=$LFS install \
    && ln -sv bash $LFS/bin/sh

# Coreutils-9.1
RUN cd $LFS/sources && tar xvf coreutils-9.1.tar.xz
RUN cd $LFS/sources/coreutils-9.1 && ./configure --prefix=/usr \
    --host=$LFS_TGT                   \
    --build=$(build-aux/config.guess) \
    --enable-install-program=hostname \
    --enable-no-install-program=kill,uptime \
    && make && make DESTDIR=$LFS install \
    && cd $LFS/sources/coreutils-9.1 && make \
    && cd $LFS/sources/coreutils-9.1 && make DESTDIR=$LFS install \
    && mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin \
    && mkdir -pv $LFS/usr/share/man/man8 \
    && mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8 \
    && sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8

# Diffutils-3.8
RUN cd $LFS/sources && tar xvf diffutils-3.8.tar.xz
RUN cd $LFS/sources/diffutils-3.8 && ./configure --prefix=/usr --host=$LFS_TGT \
    && make && make DESTDIR=$LFS install

# File-5.42
RUN cd $LFS/sources && tar xvf file-5.42.tar.gz
RUN cd $LFS/sources/file-5.42 && mkdir build && cd build && ../configure --disable-bzlib \
    --disable-libseccomp \
    --disable-xzlib      \
    --disable-zlib
RUN cd $LFS/sources/file-5.42/build && make
RUN cd $LFS/sources/file-5.42 && bash -c ./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess) \
    && make FILE_COMPILE=$(pwd)/build/src/file && make DESTDIR=$LFS install

# Findutils-4.9.0
RUN cd $LFS/sources && tar xvf findutils-4.9.0.tar.xz
RUN cd $LFS/sources/findutils-4.9.0 && ./configure --prefix=/usr \
    --localstatedir=/var/lib/locate \
    --host=$LFS_TGT                 \
    --build=$(build-aux/config.guess) \
    && make && make DESTDIR=$LFS install

# Gawk-5.1.1
RUN cd $LFS/sources && tar xvf gawk-5.1.1.tar.xz
RUN cd $LFS/sources/gawk-5.1.1 && sed -i 's/extras//' Makefile.in
RUN cd $LFS/sources/gawk-5.1.1 && ./configure --prefix=/usr   \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess) \
    && make && make DESTDIR=$LFS install

# Grep-3.7
RUN cd $LFS/sources && tar xvf grep-3.7.tar.xz
RUN cd $LFS/sources/grep-3.7 && ./configure --prefix=/usr --host=$LFS_TGT \
    && make && make DESTDIR=$LFS install

# Gzip-1.12
RUN cd $LFS/sources && tar xvf gzip-1.12.tar.xz
RUN cd $LFS/sources/gzip-1.12 && ./configure --prefix=/usr --host=$LFS_TGT \
    && make && make DESTDIR=$LFS install

# Make-4.3
RUN cd $LFS/sources && tar xvf make-4.3.tar.gz
RUN cd $LFS/sources/make-4.3 && ./configure --prefix=/usr   \
    --without-guile \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess) \
    && make && make DESTDIR=$LFS install

# Patch-2.7.6
RUN cd $LFS/sources && tar xvf patch-2.7.6.tar.xz
RUN cd $LFS/sources/patch-2.7.6 && ./configure --prefix=/usr   \
    --host=$LFS_TGT \
    --build=$(build-aux/config.guess) \
    && make && make DESTDIR=$LFS install

# Sed-4.8
RUN cd $LFS/sources && tar xvf sed-4.8.tar.xz
RUN cd $LFS/sources/sed-4.8 && ./configure --prefix=/usr --host=$LFS_TGT \
    && make && make DESTDIR=$LFS install

# Tar-1.34
RUN cd $LFS/sources && tar xvf tar-1.34.tar.xz
RUN cd $LFS/sources/tar-1.34 && ./configure --prefix=/usr \
    --host=$LFS_TGT                   \
    --build=$(build-aux/config.guess)
RUN cd $LFS/sources/tar-1.34 && make
RUN cd $LFS/sources/tar-1.34 && make DESTDIR=$LFS install

# Xz-5.2.6
RUN cd $LFS/sources && tar xvf xz-5.2.6.tar.xz
RUN cd $LFS/sources/xz-5.2.6 && ./configure --prefix=/usr \
    --host=$LFS_TGT                   \
    --build=$(build-aux/config.guess) \
    --disable-static                  \
    --docdir=/usr/share/doc/xz-5.2.6 \
    && make && make DESTDIR=$LFS install
RUN rm -v $LFS/usr/lib/liblzma.la

# Binutils-2.39 - Pass 2
RUN cd $LFS/sources/binutils-2.39 && sed '6009s/$add_dir//' -i ltmain.sh
RUN cd $LFS/sources/binutils-2.39 && mkdir -v build2
RUN cd $LFS/sources/binutils-2.39/build2 && ../configure \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd \
    && make && make DESTDIR=$LFS install
RUN bash -c "rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes}.{a,la}"

# GCC-12.2.0 - Pass 2
RUN cd $LFS/sources/gcc-12.2.0 && mkdir -v build2 && cd build2 && ../configure \
    --build=$(../config.guess)                     \
    --host=$LFS_TGT                                \
    --target=$LFS_TGT                              \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc      \
    --prefix=/usr                                  \
    --with-build-sysroot=$LFS                      \
    --enable-initfini-array                        \
    --disable-nls                                  \
    --disable-multilib                             \
    --disable-decimal-float                        \
    --disable-libatomic                            \
    --disable-libgomp                              \
    --disable-libquadmath                          \
    --disable-libssp                               \
    --disable-libvtv                               \
    --enable-languages=c,c++ \
    && make && make DESTDIR=$LFS install && ln -sv gcc $LFS/usr/bin/cc
