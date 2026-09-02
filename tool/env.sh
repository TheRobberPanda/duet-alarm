# Source this before any Flutter work:  source tool/env.sh
# To make it permanent, append these lines to ~/.bashrc.
#
# Note: the system Java is a JRE with no compiler, so Gradle needs this JDK.
export JAVA_HOME="$HOME/development/jdk21"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$HOME/development/flutter/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
