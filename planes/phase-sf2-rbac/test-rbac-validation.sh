#!/bin/bash
# Test script to demonstrate RBAC validation from SF-2 requirements
# Shows the expected output format for kubectl auth can-i commands

echo "=== SF-2 RBAC Validation Test ==="
echo "This script shows the expected validation command format."
echo
echo "After deploying the RBAC baseline, run these commands to verify:"
echo
echo "1. Check temporal-server permissions:"
echo "   kubectl auth can-i --list --as=system:serviceaccount:control-plane:temporal-server"
echo
echo "2. Check kyverno permissions:"
echo "   kubectl auth can-i --list --as=system:serviceaccount:control-plane:kyverno"
echo
echo "3. Check postgres permissions:"
echo "   kubectl auth can-i --list --as=system:serviceaccount:data-plane:postgres"
echo
echo "4. Check vmagent permissions:"
echo "   kubectl auth can-i --list --as=system:serviceaccount:observability-plane:vmagent"
echo
echo "Expected output should show minimal permissions like:"
echo "Resources                                       Non-Resource URLs   Resource Names   Verbs"
echo "pods                                            []                  []               [get list watch]"
echo "services                                        []                  []               [get list watch]"
echo "configmaps                                      []                  []               [get list watch]"
echo
echo "The validation script (sf2-rbac-validate.sh) automates these checks."
echo
echo "To run the full validation suite:"
echo "./planes/sf2-rbac-validate.sh"