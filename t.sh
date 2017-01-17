#!/bin/sh

export WORLD=$(cd "$(dirname "$0")" && pwd)
. $(cd $(dirname "$0") && pwd)/config.sh

# sh scripts/arm.sh --release=3.4 c
# sh scripts/arm.sh --release=3.4 b --output=out-3.4-x86_64 testing/sane testing/hplip
# sh scripts/arm.sh --release=3.4 e -b testing/hplip:ww
# sh scripts/arm.sh e -b source/undup:ww
# sh scripts/arm.sh e "$@"
# sh scripts/arm.sh keygen --name='Alejandro Liu' --email='alejandro_liu@hotmail.com'
# sh scripts/arm.sh b --output=out testing/dos2unix
# sh scripts/arm.sh b --output=out source/ted
# sh scripts/arm.sh apkindex --keystore=out out
# sh scripts/arm.sh depsort source testing
# sh scripts/arm.sh u "$@"
 

#sh scripts/arm.sh c
#sh scripts/arm.sh b --output=out-3.4-x86_64 testing/hplip
#sh scripts/arm.sh apkindex --keystore=out-3.4-x86_64 out-3.4-x86_64

# sh scripts/arm.sh n
sh scripts/arm.sh "$@"
