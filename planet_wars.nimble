version     = "0.1.0"
author      = "treeform@softmax.com"
description = "Planet Wars Coworld game."
license     = "MIT"

srcDir = "src"
bin = @["planet_wars"]

switch("threads", "on")
switch("mm", "orc")

requires "nim >= 2.2.4"
requires "bitworld >= 0.1.0"
requires "fluffy >= 1.0.0"
requires "jsony"
requires "mummy >= 0.4.7"
requires "supersnappy >= 2.1.3"
requires "whisky >= 0.1.3"
