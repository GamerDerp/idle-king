extends Node
## Autoload `Fmt`: every number shown on screen goes through Fmt.num().
## Thin wrapper around the static NumFmt (scripts/core/num_fmt.gd).


func num(x: float) -> String:
	return NumFmt.num(x)


func sci(x: float) -> String:
	return NumFmt.sci(x)


func time(seconds: float) -> String:
	return NumFmt.time(seconds)
