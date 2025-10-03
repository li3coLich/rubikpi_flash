#!/bin/bash
set -e

# --- Argument parsing ---
if [ -z "$1" ]; then
  echo "Usage: $0 <robot_idx> [distro]"
  echo "  robot_idx : integer robot number"
  echo "  distro    : (optional) ros2 distro (humble or jazzy), default=jazzy"
  exit 1
fi

ROBOT_IDX=$1
ROS_DISTRO=${2:-jazzy}   # default to jazzy
ROS_DOMAIN_ID=$((ROBOT_IDX + 100))

echo "=== Robot Index: $ROBOT_IDX ==="
echo "=== ROS_DISTRO : $ROS_DISTRO ==="
echo "=== ROS_DOMAIN_ID : $ROS_DOMAIN_ID ==="

# ---------------------------
# STEP 1: Locale Setup
# ---------------------------
echo "=== Setting up locale ==="
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# ---------------------------
# STEP 2: Add ROS 2 Repository
# ---------------------------
echo "=== Adding ROS 2 apt repository ==="
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg

echo "deb [arch=arm64 signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
http://packages.ros.org/ros2/ubuntu noble main" | \
    sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

# ---------------------------
# STEP 3: Install ROS 2 Core
# ---------------------------
echo "=== Installing ROS 2 $ROS_DISTRO ==="
sudo apt-get update --fix-missing
sudo apt-get install -y ros-${ROS_DISTRO}-desktop

# ---------------------------
# STEP 4: Extra ROS Packages
# ---------------------------
echo "=== Installing extra ROS 2 packages ==="
sudo apt-get install -y ros-${ROS_DISTRO}-image-transport-plugins
sudo apt-get install -y ros-${ROS_DISTRO}-foxglove-bridge
sudo apt-get install -y ros-${ROS_DISTRO}-camera-calibration
sudo apt-get install -y ros-${ROS_DISTRO}-apriltag ros-${ROS_DISTRO}-apriltag-msgs
sudo apt-get install -y ros-${ROS_DISTRO}-teleop-twist-keyboard

# ---------------------------
# STEP 5: System dependencies
# ---------------------------
echo "=== Installing system libraries for camera and vision ==="
sudo apt-get install -y pkg-config \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  libopencv-dev libv4l-dev libjpeg-turbo8-dev libpng-dev libtiff-dev libapriltag-dev

sudo apt-get install -y python3-pip python3-colcon-common-extensions

# ---------------------------
# STEP 6: Rubik Pi Camera Packages
# ---------------------------
echo "=== Adding Thundercomm Rubik Pi repo ==="
sudo sed -i '$a deb http://apt.thundercomm.com/rubik-pi-3/noble ppa main' /etc/apt/sources.list
sudo apt update
sudo apt install -y qcom-ib2c qcom-camera-server qcom-camx
sudo apt install -y rubikpi3-cameras
sudo apt install -y gstreamer1.0-qcom-sample-apps

echo "=== Configuring camera cache ==="
sudo chmod -R 777 /opt
sudo mkdir -p /var/cache/camera/
echo "enableNCSService=FALSE" | sudo tee /var/cache/camera/camxoverridesettings.txt > /dev/null

# ---------------------------
# STEP 7: OV5647 Driver Files
# ---------------------------
echo "=== Installing OV5647 camera drivers (if found) ==="
SRC_DIR=$(pwd)
DEST_DIR="/usr/lib/camera"
sudo mkdir -p "$DEST_DIR"

for f in com.qti.sensor.ov5647.so \
         com.qti.sensor.ov5647.so.0 \
         com.qti.sensor.ov5647.so.0.1.0 \
         com.qti.sensormodule.cam1_ov5647.bin \
         com.qti.sensormodule.cam2_ov5647.bin; do
    if [ -f "$SRC_DIR/$f" ]; then
        echo "Copying $f -> $DEST_DIR"
        sudo cp "$SRC_DIR/$f" "$DEST_DIR/"
    else
        echo "Warning: $f not found in $SRC_DIR"
    fi
done

# ---------------------------
# STEP 8: Setup ROS Environment
# ---------------------------
ROS_SETUP="/opt/ros/${ROS_DISTRO}/setup.bash"
if [ -f "$ROS_SETUP" ]; then
  echo "source $ROS_SETUP" >> ~/.bashrc
  echo "export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}" >> ~/.bashrc
  echo "=== Added ROS setup and ROS_DOMAIN_ID to ~/.bashrc ==="
fi

# ---------------------------
# STEP 9: ROS 2 Workspace
# ---------------------------
echo "=== Creating ROS 2 workspace and cloning rubikpi_ros2 ==="
mkdir ~/ros2_ws
cd ~/ros2_ws
if [ ! -d "rubikpi_ros2" ]; then
  git clone https://github.com/AutonomousVehicleLaboratory/rubikpi_ros2.git
else
  echo "rubikpi_ros2 repo already exists, skipping clone."
fi

# ---------------------------
# STEP 10: Restart Camera Server
# ---------------------------
echo "=== Restarting cam-server ==="
sudo systemctl restart cam-server || echo "cam-server service not found"

sudo usermod -a -G dialout $USER
python3 -m pip install --break-system-packages pynput

# ---------------------------
# STEP 11: Reboot
# ---------------------------
echo "=================================================="
echo "✅ Installation complete!"
echo "ROS_DISTRO    = $ROS_DISTRO"
echo "ROS_DOMAIN_ID = $ROS_DOMAIN_ID"
echo "Workspace     = ~/ros2_ws/src/rubikpi_ros2"
echo "System will reboot in 5 seconds..."
echo "=================================================="
sleep 5
sudo reboot
