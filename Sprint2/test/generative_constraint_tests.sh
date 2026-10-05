#!/bin/sh

    psql -d test_db -v ON_ERROR_STOP=1 -f test/generative_constraint_tests.sql