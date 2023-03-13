# Pandoc filter for in-line ROOT code


This targets only html and latex output. In the case of html output, the default is to generate interactive plots with jsroot. 

Code to execute belongs is a codeblock with  a .ROOT tag 
Code here acts as if equivalent to all code living inside a function "void main()", concatenated in order of appearance. 


```{.ROOT} 

TH1I hist ("my_hist","My Histogram;foo",100,-10,10); 

```
If, however, you set pre="true", this will appear before outside the function (in the order called),  which can be used for e.g. loading macros or libraries or defining helper functions. 


```{.ROOT pre="true"}

double square(double x) { return x*x; } 

```


```{.ROOT}

for (int i = 0; i < 100; i++)
{
   hist.Fill(gRandom->Gaus(-1) + 0.5 * gRandom->Gaus(0)  + square(gRandom->Gaus(1)) ); 
}


```


Ok, but how do you get output? 
To get a plot, add a plot option with the name of a canvas (or pad), which will place a plot ``here" (with a loose definition of here for latex)


```{.ROOT plot="c1"}
// you can have whatever setup code in here you want. The plot is executed at the end. 
TCanvas * c = new TCanvas("c1","c1",800,600); 
hist.DrawCopy(); //because hist will go out of scope otherwise 
```

You can optionally specify a format, if you don't want to use the default (pdf for latex output, jsroot for html output). 
Allowed formats are: 

 - pdf (latex, note that `gStyle->SetLineWidthPS(1)` is implicitly called at the begining of the preamble, but you can overwrrite)
 - eps (latex)
 - png (latex or html) 
 - jpg (latex or html) 
 - svg (html) 
 - jsroot (html, this saves a ROOT file with the TCanvas and uses JSRoot to plot the canvas) 


```{.ROOT plot="c1" format="png"} 
//it's ok to have an empty plot code block... 
```


If you want to enable output, you can add set the echo option to true, which will enable echoing stdout within this block (supported only in main!). Note that if a plot is emitted in the same block, the text will appear first. 

```{.ROOT echo="true"} 

std::cout << hist.GetEntries() << std::endl; //NB: you could use `using namespace std` in the pre section to avoid having to namespace std

```


Another way to get values out of the script is to use the inline `!.ROOT(x)`
construction, which will output the value of the expression x at that point in
main.  For example we can print out that the square of 13 is !.ROOT(square(13))
like that. However, if you have pandoc older than 2.17, this may not work as
expected because it requires topdown traversal to process things in order they
appear in the file. Instead, codeblocks will be processed first and then all
inline elements, allowing you to workaround ordering by introducing variables
to store the state at a given time. 



