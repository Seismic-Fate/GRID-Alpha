TABLE status, risk-class, owner, implementer, reviewer

FROM "01-work-packages"

WHERE file.name != "README"

SORT status ASC, file.name ASC

