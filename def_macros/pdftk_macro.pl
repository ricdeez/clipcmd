#--def_macro pdftk
# --------------------------------------------------------
# list needs to conform to
# -- pdftk
# 1.pdf
# 2.pdf
# this is a long filename with spaces.pdf
# needs clipcommand.pl running
# --------------------------------------------------------
use List::MoreUtils qw(zip);
# say $Bin;
my @a = ('A'..'Z');
my @b;
while (<>){
    chomp;
    push @b, $_;
}

my @c = @a[0.. $#b]; #zip doesn't work properly if lists aren't the same length
my %files = zip @c, @b;
my $string;
$string .= "pdftk ";
$string .= join " ", map { "$_->[0]=\"$_->[1]\"" }
                sort { $a->[0] cmp $b->[0] } 
                map  {[ $_, $files{$_} ]   } sort keys %files;
$string .= " cat ";         
$string .= join " ", map { "$_" . "1-end" } sort keys %files;
$string .= " output output.pdf";
print $string;
#-- promote_macro pdftk 
#-- exit