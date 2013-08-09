#############################################################################################################
# Copyright (c) 2006, by EDS                                                   
#############################################################################################################
#	Modification log:                                                            
# 	Date       		Name                    Description                    
# 	dd/mm/yy                                                                 
# 	--------   		----                    -----------                    
# 	06/04/02   		Steven Druyts           Initial release                                     #
# 	10/02/06   		Steven Druyts           P02.00.00 : binary, more general approach           #
#############################################################################################################

package MyIp;

use strict;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw( $IPPAT $IPNETPAT $PORTTYPEPAT $PORTPAT
	FindNetwork ConvBinToIp ConvIpToBin ConvDecToBin ConvBinToDec IsValidIp IsValidMask IsValidIpNet NetToMask IsValidNet
	IpNetToIpAndMask MaskToAccessMask IsNetwork SubnetSize FindIpInRange IsValidDeviceIp IsBroadcast IsInNetwork IsInNetworks IsNotNetworkIp 
	IsValidDevInNetworks IsNotIpXInNw IsValidPort IsValidPortType IsIpXInNw);

my $Version = "P02.00.00";

##  For IP Version 4


our $IPPAT='(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})';
our $IPNETPAT=$IPPAT.'/(\d{1,2})';
our $PORTPAT='^\d{1,5}$';
our $PORTTYPEPAT='^(tcp|udp)$';


sub FindNetwork{  # input : ipaddress and mask, output : network address
	return ConvBinToIp( ConvIpToBin(shift) & ConvIpToBin(shift) )
}

sub ConvBinToIp{  # input : 32 bit pattern, output : ipaddress
	return join '.', map( ConvBinToDec($_), ( +shift =~ /^([01]{8})([01]{8})([01]{8})([01]{8})$/) )
}

sub ConvIpToBin{   # input : IP address, output : 32 bit pattern
	return join "", map( ConvDecToBin($_,8),split /\./, shift)
}

sub ConvDecToBin{	# input : decimal, output : binary with length $length
	my ($dec,$length)=@_;
	my $bin="";
		
	for (my $i=$length-1; $i>=0; $i--){
		my $bit = ($dec>>$i);
		$bin.=$bit;
		$dec -= $bit*(1<<$i);
	}
	
	#print "bin is $bin\n";
	
	return $bin
}

sub ConvBinToDec{	# input : binary, output : decimal
	my @bits=split //, shift;
	my $dec=0;
	my $i=0; 
	my $j=$#bits;

	while ( $j >= 0 ){
		$dec += $bits[$j] * (1<<$i);
		$i++;
		$j--;
	}
	return $dec
}

sub IsValidIp{		# input : ip address ; out : 1 or "" 
	my $ip=shift;
	$ip=~s/\s*|\*$//g;
	return 0 unless  $ip =~ /^$IPPAT$/;
	return ConvIpToBin($ip) =~ /^[01]{32}$/
}

sub IsValidMask{	# input : subnetmask     out : 1 or ""   e.g. 255.255.255.224  -> 1
	my $msk=shift;
	return IsValidIp($msk) && ConvIpToBin($msk) =~ /^(1*)0*$/
}

sub IsValidIpNet{	# input : ip address/nr of nw bits    out : 1 or ""   e.g.  172.13.12.4/29  -> 1; 172.13.12.480/29 -> "" 
	my ($ip,$nwbits)=(+ shift =~ m!(.*)/(.*)!);
	return IsValidIp($ip) && IsValidNet($nwbits)
}


sub NetToMask{  # input is nr of nw bits; output is subnetmask
	my $net=shift;
		
	if ( IsValidNet($net)){
		return ConvBinToIp(("1" x $net ).("0" x (32 - $net)))
	}else{
		return 0
	}
}

sub IsValidNet{	# input is nr of nw bits; output is 1 or 0
	my $net=shift;
	return ($net =~ /^\d+$/) && ($net <= 32) && ($net >= 0)
}

sub IpNetToIpAndMask{  # input : Ip address/nr of nw bits   out : (ip address,subnetmask)   e.g.  172.13.12.4/29 -> (172.13.12.4,255.255.255.248)    
	my $ipnet=shift;
	
	if ( IsValidIpNet($ipnet)){
		my ($ip,$nwbits)=($ipnet =~ m!(.*)/(.*)!);
		return ($ip,NetToMask($nwbits))
	}else{
		return 0
	}
}

sub MaskToAccessMask{  # input : subnetmask   out : access list mask     e.g.  255.255.255.224 -> 0.0.0.31
	my $mask=shift;

	if ( IsValidMask($mask)){
		return ConvBinToIp(join "", map( $_ ^ 1, split //,ConvIpToBin($mask))  ) 
	}else{
		return 0
	}
}


sub IsNetwork{	# input : ipaddress and mask; output : 1 or 0
  	my ($ip,$mask)=@_;
	return IsValidIp($ip) && IsValidMask($mask) && FindNetwork($ip,$mask) eq $ip
}


sub IsNotNetworkIp{
	my ($ip,$mask)=@_;
	return IsValidIp($ip) && IsValidMask($mask) && FindNetwork($ip,$mask) ne $ip
}

sub FindIpInRange{	#returns address nr $nr on network $nw with mask $mask
   	my($nw,$mask,$nr)=@_;

	#print "FindIpInRange called with network $nw, mask $mask, nr $nr\n";

   	if ( $nr >= SubnetSize($mask) ){
		#print "ERROR in FindIpInRange : $nr too big for mask $mask\n";
		return 0
   	}elsif( ! IsNetwork($nw,$mask) ){
		#print "ERROR in FindIpInRange : $nw with mask $mask is not a network address\n";
		return 0
   	}else{
		return ConvBinToIp(ConvDecToBin($nr,32) | ConvIpToBin($nw) )
   	}
}

sub SubnetSize{	# input : mask;  output : size of subnet, e.g. ,4,8,32,...
      
	my $nwbits=0;
	my $bin=ConvIpToBin(shift);
	$nwbits++ while $bin =~ /1/g;

	return 2**(32 - $nwbits)
}


sub IsValidDeviceIp{	# Takes into account the subnetmask / Network|Broadcast address
	my($ip,$mask)=@_;
	return IsValidIp($ip) && IsValidMask($mask) && !IsNetwork($ip,$mask) && !IsBroadcast($ip,$mask)
}


sub IsBroadcast{	# assumes Is_Valid_IP($IP) and Is_Valid_Mask($mask)
	my($ip,$mask)=@_;
	my $nw=FindNetwork($ip,$mask);
	my $broadcast=SubnetSize($mask) - 1;

	return $ip eq FindIpInRange($nw,$mask,$broadcast)
}


sub IsInNetwork{     # in : ip address, network address and mask;  out : 1 if ip is in range; 0 otherwise
	my ($ip,$nw,$mask,$strict)=@_;

	return FindNetwork($ip,$mask) eq $nw
}

sub IsInNetworks{    # in : ip address, and hash of network/masks;  out : 1 if ip is in these ranges; 0 otherwise

	my $ip=shift;
	my %nw_masks=@_;
	my $ok=0;
	
	for my $nw ( keys %nw_masks){
		$ok= IsInNetwork($ip,$nw,$nw_masks{$nw});
		#$ok &&= IsValidDeviceIp($ip,$nw_masks{$nw});
		last if $ok
	}
	
	return $ok
}


sub IsValidDevInNetworks{

	my $ip=shift;
	my %nw_masks=@_;
	my $ok=0;
	
	for my $nw ( keys %nw_masks){
		$ok= IsInNetwork($ip,$nw,$nw_masks{$nw}) && IsValidDeviceIp($ip,$nw_masks{$nw});
		last if $ok
	}
	
	return $ok

}


sub IsNotIpXInNw{    # in : ip, nw address and mask, and nr(s);   out : 1 if valid ip and ip is not one of the given nrs in range
	my ($ip,$nw,$mask,$nr)=@_;
	
	my @ips;
	
	my $ok=IsValidIp($ip);
		
	if ( ref($nr) ne 'ARRAY' ){
		@ips=($nr);
	}else{
		@ips=@$nr;
	}
	
	for (@ips){ $ok &&= $ip ne FindIpInRange($nw,$mask,$_);  }
	
	return $ok
}


sub IsIpXInNw{    # in : ip, nw address and mask, and nr(s);   out : 1 if valid ip and ip is the given nr in the network
	my ($ip,$nw,$mask,$nr)=@_;
	return IsValidIp($ip) && ( $ip eq FindIpInRange($nw,$mask,$nr) )
}


sub IsValidPort{
	my $port=shift;
	return 0 unless $port =~ /^\d+$/;
	return ( $port > 0 ) && ( $port <= 65536 )
}

sub IsValidPortType{
	my $type=shift;
	return $type =~ /$PORTTYPEPAT/
}

1;
__END__
