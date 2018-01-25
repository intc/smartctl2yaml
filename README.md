# smartctl2yaml
A Perl script to convert "smartctl -a" or "smartctl -x" output to YAML or JSON format
## Usage
```
smartctl2yaml.pl [options]
```
## Options
```
OPTIONS: --help, -h
           Show this help.
         --outformat, -o [yaml/json]
           Select output format. (Default: json)
```
## Example
```
# smartctl -x /dev/sda | perl smartctl2yaml.pl -o yaml > smartctl_sda.yaml
```
## Authors
* **Antti Antinoja** - [intc](https://github.com/intc)
