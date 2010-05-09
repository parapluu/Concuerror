TODO
=====
* receive order problem (η rep_receive επιστρέφει μετά την αποτίμηση των
  εκφράσεων στο σώμα του clause που έκανε match, συνεπώς το receive φαίνεται
  σαν να γίνεται μετά από οτιδήποτε βρίσκεται μέσα στις εκφράσεις αυτές)!
* replace anonymous variables
* fix hardcode variable names (Aux, SenderPid)
* mod:fun/number_of_args εκτός από lid
* remove ets tables (maybe)
* και άλλο ένα &lt;TODO> στο exit, στις περιπτώσεις που το
  αποτέλεσμα ενός process είναι προφανές, όπως για παράδειγμα
  όταν τελειώνει με receive που ξέρουμε τι επιστρέφει
