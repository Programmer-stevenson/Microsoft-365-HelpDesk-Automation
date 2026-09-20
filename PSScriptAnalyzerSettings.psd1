@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        # Write-Host is intentional for interactive help-desk operator feedback.
        'PSAvoidUsingWriteHost'
    )
}
