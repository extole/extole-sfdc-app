#!/bin/bash
defaults write com.apple.screencapture location "/Users/christopherduskin/extole-sfdc-app"
killall SystemUIServer
echo "Screenshot location set to /Users/christopherduskin/extole-sfdc-app"
