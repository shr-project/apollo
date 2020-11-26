#!/bin/bash

# Copyright (c) 2020 LG Electronics, Inc. All Rights Reserved

set -e

if [ "$1" == "rebuild" ] ; then
  DEV_START__BUILD_ONLY__LGSVL=1 docker/scripts/dev_start.sh
  docker exec -u $USER -t apollo_dev_$USER bazel clean --expunge || true
  docker exec -u $USER -t apollo_dev_$USER /apollo/apollo.sh build_opt_gpu
fi

# Expects that the Apollo was already built in apollo_dev_$USER
if ! docker exec -u $USER -t apollo_dev_$USER ls /apollo/.cache/bazel >/dev/null; then
  echo "ERROR: apollo_dev_$USER isn't running or doesn't have /apollo/.cache/bazel directory"
  echo "       make sure it's running (you can use docker/scripts/dev_start.sh)"
  echo "       and build Apollo there or add \"rebuild\" parameter to this script"
  echo "       and it will be started and built automatically"
  exit 1
fi

docker build -f docker/build/runtime.x86_64.dockerfile docker/build/ -t lgsvl/apollo-6.0-runtime

docker stop apollo_runtime_$USER || true
docker rm apollo_runtime_$USER || true
docker run -it -d --name apollo_runtime_$USER lgsvl/apollo-6.0-runtime /bin/bash
docker commit -m "Without prebuilt files" apollo_runtime_$USER

# Copy apollo repository
docker exec apollo_runtime_$USER mkdir /apollo
docker exec apollo_runtime_$USER mkdir /usr/local/apollo
tar -cf - --exclude ./.cache/bazel/install --exclude ./.cache/bazel/cache --exclude ./.cache/build --exclude ./.cache/distdir --exclude ./.cache/repos --exclude=./modules/map/data/* --exclude=./data/log/* --exclude=**/.git --exclude=**/_objs --exclude=**/*.a --exclude=./lgsvlsimulator-output . | docker cp -a - apollo_runtime_$USER:/apollo

grep -v ^# docker/build/installers/install_apollo_files.txt > docker/build/installers/install_apollo_files.txt.tmp
docker exec apollo_dev_$USER sh -c 'tar -C / -cf - --files-from=/apollo/docker/build/installers/install_apollo_files.txt.tmp' | docker cp -a - apollo_runtime_$USER:/
rm -f docker/build/installers/install_apollo_files.txt.tmp

# Copy in the contents of the mounted volumes.
# dev container contains following volumes:
# apolloauto/apollo           faster_rcnn_volume-traffic_light_detection_model-latest          58537bb25841        2 months ago        170MB
# apolloauto/apollo           yolov4_volume-emergency_detection_model-latest                   e3e249ea7a8a        2 months ago        264MB
# apolloauto/apollo           localization_volume-x86_64-latest                                109001137d4a        17 months ago       5.44MB
# apolloauto/apollo           data_volume-audio_model-x86_64-latest                            17cb2a72a392        2 months ago        194MB
# apolloauto/apollo           map_volume-san_mateo-latest                                      48cd73de58ba        13 months ago       202MB
# apolloauto/apollo           map_volume-sunnyvale_with_two_offices-latest                     93a347cea6a0        8 months ago        509MB
# apolloauto/apollo           map_volume-sunnyvale_big_loop-latest                             e7b1a71d5b9d        8 days ago          440MB
# apolloauto/apollo           map_volume-sunnyvale_loop-latest                                 36dc0d1c2551        2 years ago         906MB
# apolloauto/apollo           local_third_party_volume-x86_64-latest                           5df2bf3cc4b9        17 months ago       156MB

# apolloauto/apollo:local_third_party_volume-x86_64-latest
docker cp apollo_local_third_party_volume_$USER:/usr/local/apollo/local_third_party - | docker cp -a - apollo_runtime_$USER:/usr/local/apollo

# apolloauto/apollo:data_volume-audio_model-x86_64-latest
docker cp apollo_audio_volume_$USER:/apollo/modules/audio/data - | docker cp -a - apollo_runtime_$USER:/apollo/modules/audio/

# apolloauto/apollo:faster_rcnn_volume-traffic_light_detection_model-latest
docker cp apollo_faster_rcnn_volume_$USER:/apollo/modules/perception/production/data/perception/camera/models/traffic_light_detection/faster_rcnn_model - | docker cp -a - apollo_runtime_$USER:/apollo/modules/perception/production/data/perception/camera/models/traffic_light_detection

# apolloauto/apollo:localization_volume-x86_64-latest
docker cp apollo_localization_volume_$USER:/usr/local/apollo/local_integ - | docker cp -a - apollo_runtime_$USER:/usr/local/apollo

# apolloauto/apollo:yolov4_volume-emergency_detection_model-latest
docker cp apollo_yolov4_volume_$USER:/apollo/modules/perception/camera/lib/obstacle/detector/yolov4/model - | docker cp -a - apollo_runtime_$USER:/apollo/modules/perception/camera/lib/obstacle/detector/yolov4

# apolloauto/apollo:map_volume-san_mateo-latest
#docker cp apollo_map_volume-san_mateo_$USER:/apollo/modules/map/data/san_mateo - | docker cp -a - apollo_runtime_$USER:/apollo/modules/map/data

# apolloauto/apollo:map_volume-sunnyvale_with_two_offices-latest
#docker cp apollo_map_volume-sunnyvale_with_two_offices_$USER:/apollo/modules/map/data/sunnyvale_with_two_offices - | docker cp -a - apollo_runtime_$USER:/apollo/modules/map/data

# apolloauto/apollo:map_volume-sunnyvale_loop-latest
#docker cp apollo_map_volume-sunnyvale_loop_$USER:/apollo/modules/map/data/sunnyvale_loop - | docker cp -a - apollo_runtime_$USER:/apollo/modules/map/data

# apolloauto/apollo:map_volume-sunnyvale_big_loop-latest
#docker cp apollo_map_volume-sunnyvale_big_loop_$USER:/apollo/modules/map/data/sunnyvale_big_loop - | docker cp -a - apollo_runtime_$USER:/apollo/modules/map/data

docker exec apollo_runtime_$USER ldconfig

cat <<! > image-info-lgsvl.source
IMAGE_APP=apollo-6.0
IMAGE_CREATED_BY=runtime.x86_64.sh
IMAGE_CREATED_FROM=$(git describe --tags --always)
IMAGE_CREATED_ON=$(date --iso-8601=seconds --utc)
# Increment IMAGE_INTERFACE_VERSION whenever changes to the image require that the launcher be updated.
IMAGE_INTERFACE_VERSION=1
IMAGE_UUID=$(uuidgen)
!

docker cp image-info-lgsvl.source apollo_runtime_$USER:/apollo/image-info-lgsvl.source
rm -f image-info-lgsvl.source

# Use apollo user with UID 1001
# This was used to be called from docker/scripts/dev_start.sh (or docker/scripts/runtime_start.sh),
# but we want the container to be as ready to use as possible out of the registry and we don't use
# $HOME/.cache anymore, so different UID in container shouldn't cause (m)any issues
docker exec -e DOCKER_GRP_ID=1001 -e DOCKER_USER_ID=1001 -e DOCKER_USER=apollo -e DOCKER_GRP=apollo apollo_runtime_$USER /apollo/scripts/docker_start_user.sh || true
docker exec apollo_runtime_$USER chown -R apollo:apollo /apollo

docker commit -m "With prebuilt files" apollo_runtime_$USER lgsvl/apollo-6.0-runtime:latest

/bin/echo -e "Docker image with prebuilt files was built and tagged as lgsvl/apollo-6.0-runtime:latest, you can start it with: \n\
  docker/scripts/runtime_start.sh\n\
and switch into it with:\n\
  docker/scripts/runtime_into.sh"
