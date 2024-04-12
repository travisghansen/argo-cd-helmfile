#!/bin/bash

yq "eval-all" ". | [.]" ${1}
